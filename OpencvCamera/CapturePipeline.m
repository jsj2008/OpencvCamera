//
//  CapturePipeline.m
//  OpencvCamera
//
//  Created by Anastasia Tarasova on 16/05/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import "CapturePipeline.h"

#import "MovieRecorder.h"

#import <CoreMedia/CMBufferQueue.h>
#import <CoreMedia/CMAudioClock.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/CGImageProperties.h>

#include <objc/runtime.h> // for objc_loadWeak() and objc_storeWeak()

/*
 RETAINED_BUFFER_COUNT is the number of pixel buffers we expect to hold on to from the renderer. This value informs the renderer how to size its buffer pool and how many pixel buffers to preallocate (done in the prepareWithOutputDimensions: method). Preallocation helps to lessen the chance of frame drops in our recording, in particular during recording startup. If we try to hold on to more buffers than RETAINED_BUFFER_COUNT then the renderer will fail to allocate new buffers from its pool and we will drop frames.
 
 A back of the envelope calculation to arrive at a RETAINED_BUFFER_COUNT of '6':
 - The preview path only has the most recent frame, so this makes the movie recording path the long pole.
 - The movie recorder internally does a dispatch_async to avoid blocking the caller when enqueuing to its internal asset writer.
 - Allow 2 frames of latency to cover the dispatch_async and the -[AVAssetWriterInput appendSampleBuffer:] call.
 - Then we allow for the encoder to retain up to 4 frames. Two frames are retained while being encoded/format converted, while the other two are to handle encoder format conversion pipelining and encoder startup latency.
 
 Really you need to test and measure the latency in your own application pipeline to come up with an appropriate number. 1080p BGRA buffers are quite large, so it's a good idea to keep this number as low as possible.
 */

#define RETAINED_BUFFER_COUNT 6

#define RECORD_AUDIO 0

#define LOG_STATUS_TRANSITIONS 0

typedef NS_ENUM( NSInteger, RosyWriterRecordingStatus )
{
    RecordingStatusIdle = 0,
    RecordingStatusStartingRecording,
    RecordingStatusRecording,
    RecordingStatusStoppingRecording,
}; // internal state machine

@interface CapturePipeline () <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, MovieRecorderDelegate>
{
    __weak id <CapturePipelineDelegate> _delegate; // __weak doesn't actually do anything under non-ARC
    dispatch_queue_t _delegateCallbackQueue;
    
    NSMutableArray *_previousSecondTimestamps;
    
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_videoDevice;
    AVCaptureConnection *_audioConnection;
    AVCaptureConnection *_videoConnection;
    BOOL _running;
    BOOL _startCaptureSessionOnEnteringForeground;
    id _applicationWillEnterForegroundNotificationObserver;
    NSDictionary *_videoCompressionSettings;
    NSDictionary *_audioCompressionSettings;
    
    dispatch_queue_t _sessionQueue;
    dispatch_queue_t _videoDataOutputQueue;
    
    //id<RosyWriterRenderer> _renderer;
    BOOL _renderingEnabled;
    
    NSURL *_recordingURL;
    RosyWriterRecordingStatus _recordingStatus;
    
    UIBackgroundTaskIdentifier _pipelineRunningTask;
}

@property(nonatomic, retain) __attribute__((NSObject)) CVPixelBufferRef currentPreviewPixelBuffer;

@property(readwrite) float videoFrameRate;
@property(readwrite) CMVideoDimensions videoDimensions;
@property(nonatomic, readwrite) AVCaptureVideoOrientation videoOrientation;

@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputVideoFormatDescription;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputAudioFormatDescription;
@property(nonatomic, retain) MovieRecorder *recorder;

@end

@implementation CapturePipeline

- (instancetype)init
{
    self = [super init];
    if ( self )
    {
        _previousSecondTimestamps = [[NSMutableArray alloc] init];
        _recordingOrientation = (AVCaptureVideoOrientation)UIDeviceOrientationPortrait;
        
        _recordingURL = [[NSURL alloc] initFileURLWithPath:[NSString pathWithComponents:@[NSTemporaryDirectory(), @"Movie.MOV"]]];
        
        _sessionQueue = dispatch_queue_create( "com.apple.sample.capturepipeline.session", DISPATCH_QUEUE_SERIAL );
        
        // In a multi-threaded producer consumer system it's generally a good idea to make sure that producers do not get starved of CPU time by their consumers.
        // In this app we start with VideoDataOutput frames on a high priority queue, and downstream consumers use default priority queues.
        // Audio uses a default priority queue because we aren't monitoring it live and just want to get it into the movie.
        // AudioDataOutput can tolerate more latency than VideoDataOutput as its buffers aren't allocated out of a fixed size pool.
        _videoDataOutputQueue = dispatch_queue_create( "com.apple.sample.capturepipeline.video", DISPATCH_QUEUE_SERIAL );
        dispatch_set_target_queue( _videoDataOutputQueue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
        
        _pipelineRunningTask = UIBackgroundTaskInvalid;
    }
    return self;
}

- (void)dealloc
{
    
    if ( _currentPreviewPixelBuffer ) {
        CFRelease( _currentPreviewPixelBuffer );
    }
    
    [self teardownCaptureSession];
    
    if ( _outputVideoFormatDescription ) {
        CFRelease( _outputVideoFormatDescription );
    }
    
    if ( _outputAudioFormatDescription ) {
        CFRelease( _outputAudioFormatDescription );
    }
}

#pragma mark Delegate

- (void)setDelegate:(id<CapturePipelineDelegate>)delegate callbackQueue:(dispatch_queue_t)delegateCallbackQueue // delegate is weak referenced
{
    if ( delegate && ( delegateCallbackQueue == NULL ) ) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Caller must provide a delegateCallbackQueue" userInfo:nil];
    }
    
    @synchronized( self )
    {
        if (delegate != _delegate) {
            _delegate = delegate;
        }
        if ( delegateCallbackQueue != _delegateCallbackQueue ) {
            _delegateCallbackQueue = delegateCallbackQueue;
        }
    }
}

- (id<CapturePipelineDelegate>)delegate
{
    id <CapturePipelineDelegate> delegate; //= nil;
    //@synchronized( self ) {
        delegate = _delegate;
   // }
    return delegate;
}

- (void)startRunningCaptureSession {
    [_captureSession startRunning];
    
    @synchronized( self )
    {
        if (self.delegate)
        {
            dispatch_async(_delegateCallbackQueue, ^{
                @autoreleasepool {
                    [self.delegate capturePipeline:self didStartRunningWithVideoDevice:_videoDevice];
                }
            });
        }
    }
}

#pragma mark - Capture Session


#pragma mark Setup CaptureSession
- (void)setupCaptureSession
{
    if ( _captureSession ) {
        return;
    }
    
    _captureSession = [[AVCaptureSession alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(captureSessionNotification:) name:nil object:_captureSession];
    _applicationWillEnterForegroundNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:[UIApplication sharedApplication] queue:nil usingBlock:^(NSNotification *note) {
        // Retain self while the capture session is alive by referencing it in this observer block which is tied to the session lifetime
        // Client must stop us running before we can be deallocated
        [self applicationWillEnterForeground];
    }];
    

    /* Audio */
    [self setupAudio];

    
    /* Video */
    [self setupVideo];
    
    return;
}

-(void)setupAudio{
    
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioIn = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:nil];
    if ( [_captureSession canAddInput:audioIn] ) {
        [_captureSession addInput:audioIn];
    }
    
    AVCaptureAudioDataOutput *audioOut = [[AVCaptureAudioDataOutput alloc] init];
    // Put audio on its own queue to ensure that our video processing doesn't cause us to drop audio
    dispatch_queue_t audioCaptureQueue = dispatch_queue_create( "com.apple.sample.capturepipeline.audio", DISPATCH_QUEUE_SERIAL );
    [audioOut setSampleBufferDelegate:self queue:audioCaptureQueue];
    
    if ( [_captureSession canAddOutput:audioOut] ) {
        [_captureSession addOutput:audioOut];
    }
    _audioConnection = [audioOut connectionWithMediaType:AVMediaTypeAudio];
    
    _audioCompressionSettings = [[audioOut recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie] copy];


}
-(void)setupVideo{
    
    if (_videoDevice == nil)
        _videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

    
    AVCaptureDeviceInput *videoIn = [[AVCaptureDeviceInput alloc] initWithDevice:_videoDevice error:nil];
    if ( [_captureSession canAddInput:videoIn] ) {
        [_captureSession addInput:videoIn];
    }
    
    AVCaptureVideoDataOutput *videoOut = [[AVCaptureVideoDataOutput alloc] init];
    videoOut.videoSettings =  @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    [videoOut setSampleBufferDelegate:self queue:_videoDataOutputQueue];
    
    // RosyWriter records videos and we prefer not to have any dropped frames in the video recording.
    // By setting alwaysDiscardsLateVideoFrames to NO we ensure that minor fluctuations in system load or in our processing time for a given frame won't cause framedrops.
    // We do however need to ensure that on average we can process frames in realtime.
    // If we were doing preview only we would probably want to set alwaysDiscardsLateVideoFrames to YES.
    videoOut.alwaysDiscardsLateVideoFrames = NO;
    
    if ( [_captureSession canAddOutput:videoOut] ) {
        [_captureSession addOutput:videoOut];
    }
    _videoConnection = [videoOut connectionWithMediaType:AVMediaTypeVideo];
    
    int frameRate;
    NSString *sessionPreset = AVCaptureSessionPresetHigh;
    CMTime frameDuration = kCMTimeInvalid;
    // For single core systems like iPhone 4 and iPod Touch 4th Generation we use a lower resolution and framerate to maintain real-time performance.
    if ( [NSProcessInfo processInfo].processorCount == 1 )
    {
        if ( [_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480] ) {
            sessionPreset = AVCaptureSessionPreset640x480;
        }
        frameRate = 15;
    }
    else
    {
#if ! USE_OPENGL_RENDERER
        // When using the CPU renderers or the CoreImage renderer we lower the resolution to 720p so that all devices can maintain real-time performance (this is primarily for A5 based devices like iPhone 4s and iPod Touch 5th Generation).
        if ( [_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720] ) {
            sessionPreset = AVCaptureSessionPreset1280x720;
        }
#endif // ! USE_OPENGL_RENDERER
        
        frameRate = 30;
    }
    
    _captureSession.sessionPreset = sessionPreset;
    
    frameDuration = CMTimeMake( 1, frameRate );
    
    NSError *error = nil;
    if ( [_videoDevice lockForConfiguration:&error] ) {
        _videoDevice.activeVideoMaxFrameDuration = frameDuration;
        _videoDevice.activeVideoMinFrameDuration = frameDuration;
        [_videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"videoDevice lockForConfiguration returned error %@", error );
    }
    
    // Get the recommended compression settings after configuring the session/device.

    _videoCompressionSettings = [[videoOut recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie] copy];
    
    self.videoOrientation = _videoConnection.videoOrientation;

}

#pragma mark CaptureSession lifecycle

- (void)startRunning
{
    dispatch_sync( _sessionQueue, ^{
        [self setupCaptureSession];
        
        [_captureSession startRunning];
        _running = YES;
    } );
}

- (void)stopRunning
{
    dispatch_sync( _sessionQueue, ^{
        _running = NO;
        
        // the captureSessionDidStopRunning method will stop recording if necessary as well, but we do it here so that the last video and audio samples are better aligned
        [self stopRecording]; // does nothing if we aren't currently recording
        
        [_captureSession stopRunning];
        
        [self captureSessionDidStopRunning];
        
        [self teardownCaptureSession];
    } );
}


- (void)teardownCaptureSession
{
    if ( _captureSession )
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_captureSession];
        
        [[NSNotificationCenter defaultCenter] removeObserver:_applicationWillEnterForegroundNotificationObserver];
        _applicationWillEnterForegroundNotificationObserver = nil;
       
        _captureSession = nil;
        
        _videoCompressionSettings = nil;
        
        _audioCompressionSettings = nil;
    }
}

- (void)captureSessionNotification:(NSNotification *)notification
{
    dispatch_async( _sessionQueue, ^{
        
        if ( [notification.name isEqualToString:AVCaptureSessionWasInterruptedNotification] )
        {
            NSLog( @"session interrupted" );
            
            [self captureSessionDidStopRunning];
        }
        else if ( [notification.name isEqualToString:AVCaptureSessionInterruptionEndedNotification] )
        {
            NSLog( @"session interruption ended" );
        }
        else if ( [notification.name isEqualToString:AVCaptureSessionRuntimeErrorNotification] )
        {
            [self captureSessionDidStopRunning];
            
            NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
            if ( error.code == AVErrorDeviceIsNotAvailableInBackground )
            {
                NSLog( @"device not available in background" );
                
                // Since we can't resume running while in the background we need to remember this for next time we come to the foreground
                if ( _running ) {
                    _startCaptureSessionOnEnteringForeground = YES;
                }
            }
            else if ( error.code == AVErrorMediaServicesWereReset )
            {
                NSLog( @"media services were reset" );
                [self handleRecoverableCaptureSessionRuntimeError:error];
            }
            else
            {
                [self handleNonRecoverableCaptureSessionRuntimeError:error];
            }
        }
        else if ( [notification.name isEqualToString:AVCaptureSessionDidStartRunningNotification] )
        {
            NSLog( @"session started running" );
        }
        else if ( [notification.name isEqualToString:AVCaptureSessionDidStopRunningNotification] )
        {
            NSLog( @"session stopped running" );
        }
    } );
}


- (void)handleRecoverableCaptureSessionRuntimeError:(NSError *)error
{
    if ( _running ) {
        [_captureSession startRunning];
        [self startRunningCaptureSession];
    }
}

- (void)handleNonRecoverableCaptureSessionRuntimeError:(NSError *)error
{
    NSLog( @"fatal runtime error %@, code %i", error, (int)error.code );
    
    _running = NO;
    [self teardownCaptureSession];
    
    @synchronized( self )
    {
        if ( self.delegate ) {
            dispatch_async( _delegateCallbackQueue, ^{
                @autoreleasepool {
                    [self.delegate capturePipeline:self didStopRunningWithError:error];
                }
            });
        }
    }
}

- (void)captureSessionDidStopRunning
{
    [self stopRecording]; // does nothing if we aren't currently recording
    [self teardownVideoPipeline];
}

- (void)applicationWillEnterForeground
{
    NSLog( @"-[%@ %@] called", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
    
    dispatch_sync( _sessionQueue, ^{
        if ( _startCaptureSessionOnEnteringForeground ) {
            NSLog( @"-[%@ %@] manually restarting session", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
            
            _startCaptureSessionOnEnteringForeground = NO;
            if ( _running ) {
                [_captureSession startRunning];
            }
        }
    } );
}

#pragma mark - Capture Pipeline

- (void)setupVideoPipelineWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription
{
    NSLog( @"-[%@ %@] called", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
    
    [self videoPipelineWillStartRunning];
    
    self.videoDimensions = CMVideoFormatDescriptionGetDimensions( inputFormatDescription );
    self.outputVideoFormatDescription = inputFormatDescription;
    //[_renderer prepareForInputWithFormatDescription:inputFormatDescription outputRetainedBufferCountHint:RETAINED_BUFFER_COUNT];
    
    /*if ( ! _renderer.operatesInPlace && [_renderer respondsToSelector:@selector(outputFormatDescription)] ) {
        self.outputVideoFormatDescription = _renderer.outputFormatDescription;
    }
    else {
        self.outputVideoFormatDescription = inputFormatDescription;
    }*/
}

// synchronous, blocks until the pipeline is drained, don't call from within the pipeline
- (void)teardownVideoPipeline
{
    // The session is stopped so we are guaranteed that no new buffers are coming through the video data output.
    // There may be inflight buffers on _videoDataOutputQueue however.
    // Synchronize with that queue to guarantee no more buffers are in flight.
    // Once the pipeline is drained we can tear it down safely.
    
    NSLog( @"-[%@ %@] called", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
    
    dispatch_sync( _videoDataOutputQueue, ^{
        if ( ! self.outputVideoFormatDescription ) {
            return;
        }
        
        self.outputVideoFormatDescription = nil;
        self.currentPreviewPixelBuffer = NULL;
        
        NSLog( @"-[%@ %@] finished teardown", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
        
        [self videoPipelineDidFinishRunning];
    } );
}

- (void)videoPipelineWillStartRunning
{
    NSLog( @"-[%@ %@] called", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
    
    NSAssert( _pipelineRunningTask == UIBackgroundTaskInvalid, @"should not have a background task active before the video pipeline starts running" );
    
    _pipelineRunningTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog( @"video capture pipeline background task expired" );
    }];
}

- (void)videoPipelineDidFinishRunning
{
    NSLog( @"-[%@ %@] called", NSStringFromClass([self class]), NSStringFromSelector(_cmd) );
    
    NSAssert( _pipelineRunningTask != UIBackgroundTaskInvalid, @"should have a background task active when the video pipeline finishes running" );
    
    [[UIApplication sharedApplication] endBackgroundTask:_pipelineRunningTask];
    _pipelineRunningTask = UIBackgroundTaskInvalid;
}

// call under @synchronized( self )
- (void)videoPipelineDidRunOutOfBuffers
{
    // We have run out of buffers.
    // Tell the delegate so that it can flush any cached buffers.
    if ( self.delegate ) {
        dispatch_async( _delegateCallbackQueue, ^{
            @autoreleasepool {
                [self.delegate capturePipelineDidRunOutOfPreviewBuffers:self];
            }
        } );
    }
}

- (void)setRenderingEnabled:(BOOL)renderingEnabled
{
    @synchronized( self ) {
        _renderingEnabled = renderingEnabled;
    }
}

- (BOOL)renderingEnabled
{
    @synchronized( self ) {
        return _renderingEnabled;
    }
}

// call under @synchronized( self )
- (void)outputPreviewPixelBuffer:(CVPixelBufferRef)previewPixelBuffer
{
    if ( self.delegate )
    {
        // Keep preview latency low by dropping stale frames that have not been picked up by the delegate yet
        self.currentPreviewPixelBuffer = previewPixelBuffer;
        
        dispatch_async( _delegateCallbackQueue, ^{
            @autoreleasepool
            {
                CVPixelBufferRef currentPreviewPixelBuffer = NULL;
                @synchronized( self )
                {
                    currentPreviewPixelBuffer = self.currentPreviewPixelBuffer;
                    if ( currentPreviewPixelBuffer ) {
                        CFRetain( currentPreviewPixelBuffer );
                        self.currentPreviewPixelBuffer = NULL;
                    }
                }
                
                if ( currentPreviewPixelBuffer ) {
                    [self.delegate capturePipeline:self previewPixelBufferReadyForDisplay:currentPreviewPixelBuffer];
                    CFRelease( currentPreviewPixelBuffer );
                }
            }
        } );
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription( sampleBuffer );
    
    if ( connection == _videoConnection )
    {
        if ( self.outputVideoFormatDescription == nil ) {
            // Don't render the first sample buffer.
            // This gives us one frame interval (33ms at 30fps) for setupVideoPipelineWithInputFormatDescription: to complete.
            // Ideally this would be done asynchronously to ensure frames don't back up on slower devices.
            [self setupVideoPipelineWithInputFormatDescription:formatDescription];
        }
        else {
            [self renderVideoSampleBuffer:sampleBuffer];
        }
    }
    else if ( connection == _audioConnection )
    {
        self.outputAudioFormatDescription = formatDescription;
        
        @synchronized( self ) {
            if ( _recordingStatus == RecordingStatusRecording ) {
                [self.recorder appendAudioSampleBuffer:sampleBuffer];
            }
        }
    }
}

- (void)renderVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    CVPixelBufferRef renderedPixelBuffer = NULL;
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp( sampleBuffer );
    
    [self calculateFramerateAtTimestamp:timestamp];
    
    // We must not use the GPU while running in the background.
    // setRenderingEnabled: takes the same lock so the caller can guarantee no GPU usage once the setter returns.
    @synchronized( self )
    {
        if ( _renderingEnabled ) {
            CVPixelBufferRef sourcePixelBuffer = CMSampleBufferGetImageBuffer( sampleBuffer );
            renderedPixelBuffer = [self.delegate renderPixelBuffer:sourcePixelBuffer];
        }
        else {
            return;
        }
    }
    
    @synchronized( self )
    {
        if ( renderedPixelBuffer )
        {
            [self outputPreviewPixelBuffer:renderedPixelBuffer];
            
            if ( _recordingStatus == RecordingStatusRecording ) {
                [self.recorder appendVideoPixelBuffer:renderedPixelBuffer withPresentationTime:timestamp];
            }
            
            CFRelease( renderedPixelBuffer );
        }
        else
        {
            [self videoPipelineDidRunOutOfBuffers];
        }
    }
}

#pragma mark - Recording

- (void)startRecording
{
    @synchronized( self )
    {
        if ( _recordingStatus != RecordingStatusIdle ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Already recording" userInfo:nil];
            return;
        }
        
        [self transitionToRecordingStatus:RecordingStatusStartingRecording error:nil];
    }
    
    MovieRecorder *recorder = [[MovieRecorder alloc] initWithURL:_recordingURL] ;
    
//#if RECORD_AUDIO
    [recorder addAudioTrackWithSourceFormatDescription:self.outputAudioFormatDescription settings:_audioCompressionSettings];
//#endif // RECORD_AUDIO
    
    CGAffineTransform videoTransform = [self transformFromVideoBufferOrientationToOrientation:self.recordingOrientation withAutoMirroring:NO]; // Front camera recording shouldn't be mirrored
    
    [recorder addVideoTrackWithSourceFormatDescription:self.outputVideoFormatDescription transform:videoTransform settings:_videoCompressionSettings];
    
    dispatch_queue_t callbackQueue = dispatch_queue_create( "com.apple.sample.capturepipeline.recordercallback", DISPATCH_QUEUE_SERIAL ); // guarantee ordering of callbacks with a serial queue
    [recorder setDelegate:self callbackQueue:callbackQueue];
    self.recorder = recorder;
    
    [recorder prepareToRecord]; // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
}

- (void)stopRecording
{
    @synchronized( self )
    {
        if ( _recordingStatus != RecordingStatusRecording ) {
            return;
        }
        
        [self transitionToRecordingStatus:RecordingStatusStoppingRecording error:nil];
    }
    
    [self.recorder finishRecording]; // asynchronous, will call us back with recorderDidFinishRecording: or recorder:didFailWithError: when done
}

#pragma mark - MovieRecorder Delegate

- (void)movieRecorderDidFinishPreparing:(MovieRecorder *)recorder
{
    @synchronized( self )
    {
        if ( _recordingStatus != RecordingStatusStartingRecording ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Expected to be in StartingRecording state" userInfo:nil];
            return;
        }
        
        [self transitionToRecordingStatus:RecordingStatusRecording error:nil];
    }
}

- (void)movieRecorder:(MovieRecorder *)recorder didFailWithError:(NSError *)error
{
    @synchronized( self ) {
        self.recorder = nil;
        [self transitionToRecordingStatus:RecordingStatusIdle error:error];
    }
}

- (void)movieRecorderDidFinishRecording:(MovieRecorder *)recorder
{
    @synchronized( self )
    {
        if ( _recordingStatus != RecordingStatusStoppingRecording ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Expected to be in StoppingRecording state" userInfo:nil];
            return;
        }
        
        // No state transition, we are still in the process of stopping.
        // We will be stopped once we save to the assets library.
    }
    
    self.recorder = nil;
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    [library writeVideoAtPathToSavedPhotosAlbum:_recordingURL completionBlock:^(NSURL *assetURL, NSError *error) {
        
        [[NSFileManager defaultManager] removeItemAtURL:_recordingURL error:NULL];
        
        @synchronized( self ) {
            if ( _recordingStatus != RecordingStatusStoppingRecording ) {
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Expected to be in StoppingRecording state" userInfo:nil];
                return;
            }
            [self transitionToRecordingStatus:RecordingStatusIdle error:error];
        }
    }];
    
}

#pragma mark Recording State Machine

// call under @synchonized( self )
- (void)transitionToRecordingStatus:(RosyWriterRecordingStatus)newStatus error:(NSError *)error
{
    SEL delegateSelector = NULL;
    RosyWriterRecordingStatus oldStatus = _recordingStatus;
    _recordingStatus = newStatus;
    
#if LOG_STATUS_TRANSITIONS
    NSLog( @"RosyWriterCapturePipeline recording state transition: %@->%@", [self stringForRecordingStatus:oldStatus], [self stringForRecordingStatus:newStatus] );
#endif
    
    if ( newStatus != oldStatus )
    {
        if ( error && ( newStatus == RecordingStatusIdle ) )
        {
            delegateSelector = @selector(capturePipeline:recordingDidFailWithError:);
        }
        else
        {
            error = nil; // only the above delegate method takes an error
            if ( ( oldStatus == RecordingStatusStartingRecording ) && ( newStatus == RecordingStatusRecording ) ) {
                delegateSelector = @selector(capturePipelineRecordingDidStart:);
            }
            else if ( ( oldStatus == RecordingStatusRecording ) && ( newStatus == RecordingStatusStoppingRecording ) ) {
                delegateSelector = @selector(capturePipelineRecordingWillStop:);
            }
            else if ( ( oldStatus == RecordingStatusStoppingRecording ) && ( newStatus == RecordingStatusIdle ) ) {
                delegateSelector = @selector(capturePipelineRecordingDidStop:);
            }
        }
    }
    
    if ( delegateSelector && self.delegate )
    {
        dispatch_async( _delegateCallbackQueue, ^{
            @autoreleasepool
            {
                if ( error ) {
                    [self.delegate performSelector:delegateSelector withObject:self withObject:error];
                }
                else {
                    [self.delegate performSelector:delegateSelector withObject:self];
                }
            }
        } );
    }
}

#if LOG_STATUS_TRANSITIONS

- (NSString *)stringForRecordingStatus:(RosyWriterRecordingStatus)status
{
    NSString *statusString = nil;
    
    switch ( status )
    {
        case RosyWriterRecordingStatusIdle:
            statusString = @"Idle";
            break;
        case RosyWriterRecordingStatusStartingRecording:
            statusString = @"StartingRecording";
            break;
        case RosyWriterRecordingStatusRecording:
            statusString = @"Recording";
            break;
        case RosyWriterRecordingStatusStoppingRecording:
            statusString = @"StoppingRecording";
            break;
        default:
            statusString = @"Unknown";
            break;
    }
    return statusString;
}

#endif // LOG_STATUS_TRANSITIONS

#pragma mark - Utilities

// Auto mirroring: Front camera is mirrored; back camera isn't
- (CGAffineTransform)transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)orientation withAutoMirroring:(BOOL)mirror
{
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    // Calculate offsets from an arbitrary reference orientation (portrait)
    CGFloat orientationAngleOffset = angleOffsetFromPortraitOrientationToOrientation( orientation );
    CGFloat videoOrientationAngleOffset = angleOffsetFromPortraitOrientationToOrientation( self.videoOrientation );
    
    // Find the difference in angle between the desired orientation and the video orientation
    CGFloat angleOffset = orientationAngleOffset - videoOrientationAngleOffset;
    transform = CGAffineTransformMakeRotation( angleOffset );
    
    if ( _videoDevice.position == AVCaptureDevicePositionFront )
    {
        if ( mirror ) {
            transform = CGAffineTransformScale( transform, -1, 1 );
        }
    }
    
    return transform;
}

static CGFloat angleOffsetFromPortraitOrientationToOrientation(AVCaptureVideoOrientation orientation)
{
    CGFloat angle = 0.0;
    
    switch ( orientation )
    {
        case AVCaptureVideoOrientationPortrait:
            angle = 0.0;
            break;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            angle = -M_PI_2;
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            angle = M_PI_2;
            break;
        default:
            break;
    }
    
    return angle;
}

- (void)calculateFramerateAtTimestamp:(CMTime)timestamp
{
    [_previousSecondTimestamps addObject:[NSValue valueWithCMTime:timestamp]];
    
    CMTime oneSecond = CMTimeMake( 1, 1 );
    CMTime oneSecondAgo = CMTimeSubtract( timestamp, oneSecond );
    
    while( CMTIME_COMPARE_INLINE( [_previousSecondTimestamps[0] CMTimeValue], <, oneSecondAgo ) ) {
        [_previousSecondTimestamps removeObjectAtIndex:0];
    }
    
    if ( [_previousSecondTimestamps count] > 1 ) {
        const Float64 duration = CMTimeGetSeconds( CMTimeSubtract( [[_previousSecondTimestamps lastObject] CMTimeValue], [_previousSecondTimestamps[0] CMTimeValue] ) );
        const float newRate = (float)( [_previousSecondTimestamps count] - 1 ) / duration;
        self.videoFrameRate = newRate;
    }
}

- (BOOL)toggleInputDevice
{
    AVCaptureDevice *currentVideoDevice = _videoDevice;
    AVCaptureDevice *nextVideoDevice = nil;
    BOOL passedCurrent = NO;
    
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device == currentVideoDevice)
        {
            passedCurrent = YES;
            continue;
        }
        if (device.connected)
        {
            nextVideoDevice = device;
            if (passedCurrent)
                break;
        }
    }
    
    if (nextVideoDevice && nextVideoDevice != _videoDevice)
    {
        dispatch_async(_sessionQueue, ^{
            _videoDevice = nextVideoDevice;
            if (_running)
            {
                [self teardownCaptureSession];
#if USE_OPENGL_RENDERER
                [self teardownVideoPipeline];
                self.outputVideoFormatDescription = nil;
#endif
                [self setupCaptureSession];
                [self startRunningCaptureSession];
            }
        });
        return YES;
    }
    return NO;
}


@end
