//
//  VideoProcessor-2.m
//  RenderCamera
//
//  Created by Anastasia Tarasova on 14/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import "VideoProcessor.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "ImageManager.h"
#import "VideoFrame.h"
#import <ImageIO/CGImageProperties.h>

#define BYTES_PER_PIXEL 4

@interface VideoProcessor ()

// Redeclared as readwrite so that we can write to the property and still be atomic with external readers.
@property (readwrite) Float64 videoFrameRate;
@property (readwrite) CMVideoDimensions videoDimensions;
@property (readwrite) CMVideoCodecType videoType;

@property (readwrite, getter=isRecording) BOOL recording;

@property (readwrite) AVCaptureVideoOrientation videoOrientation;


@end

@implementation VideoProcessor

@synthesize delegate;
@synthesize videoFrameRate, videoDimensions, videoType;
@synthesize referenceOrientation;
@synthesize videoOrientation;
@synthesize recording;
//@synthesize movieURL;


- (id) init {
    if (self = [super init]) {
        previousSecondTimestamps = [[NSMutableArray alloc] init];
        referenceOrientation = AVCaptureVideoOrientationLandscapeLeft;
        
        //self.movieURL = [self newMovieURL];
        // The temporary path for the video before saving it to the photo album
        movieURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"ARMovie.mp4"]];
    }
    return self;
}

#pragma mark - Utilities

- (NSURL*) newMovieURL {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString *movieName = [NSString stringWithFormat:@"%f.mp4",[[NSDate date] timeIntervalSince1970]];
    NSURL *newMovieURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", basePath, movieName]];
    NSLog(@"newMovieURL      %@",[newMovieURL absoluteString]);
    return newMovieURL;
}

- (void) calculateFramerateAtTimestamp:(CMTime) timestamp {
    [previousSecondTimestamps addObject:[NSValue valueWithCMTime:timestamp]];
    
    CMTime oneSecond = CMTimeMake( 1, 1 );
    CMTime oneSecondAgo = CMTimeSubtract( timestamp, oneSecond );
    
    while( CMTIME_COMPARE_INLINE( [[previousSecondTimestamps objectAtIndex:0] CMTimeValue], <, oneSecondAgo ) )
        [previousSecondTimestamps removeObjectAtIndex:0];
    
    Float64 newRate = (Float64) [previousSecondTimestamps count];
    self.videoFrameRate = (self.videoFrameRate + newRate) / 2;
}

- (void)removeFile:(NSURL *)fileURL {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filePath = [fileURL path];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL success = [fileManager removeItemAtPath:filePath error:&error];
        if (!success)
            [self showError:error];
    }
}

- (CGFloat)angleOffsetFromPortraitOrientationToOrientation:(AVCaptureVideoOrientation)orientation {
    CGFloat angle = 0.0;
    
    switch (orientation) {
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

- (CGAffineTransform)transformFromCurrentVideoOrientationToOrientation:(AVCaptureVideoOrientation)orientation {
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    // Calculate offsets from an arbitrary reference orientation (portrait)
    CGFloat orientationAngleOffset = [self angleOffsetFromPortraitOrientationToOrientation:orientation];
    CGFloat videoOrientationAngleOffset = [self angleOffsetFromPortraitOrientationToOrientation:self.videoOrientation];
    
    // Find the difference in angle between the passed in orientation and the current video orientation
    CGFloat angleOffset = orientationAngleOffset - videoOrientationAngleOffset;
    transform = CGAffineTransformMakeRotation(angleOffset);
    
    return transform;
}

/*- (CGAffineTransform)transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)orientation withAutoMirroring:(BOOL)mirroring{

}*/

#pragma mark - Recording

- (void)saveMovieToCameraRoll {
    // added example to save a local copy of the file
    NSString *documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSURL *movieURLD = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", documentsDirectory, @"ARMovie.mp4"]];
    NSString *strDest = [NSString stringWithFormat:@"%@/%@", documentsDirectory, @"ARMovie.mp4"];
    NSString *strSrc = [NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"ARMovie.mp4"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    // delete any previous copy of the file
    if ([fileManager fileExistsAtPath:strDest] && [fileManager isWritableFileAtPath:strDest]) {
        if (![fileManager removeItemAtPath:strDest error:&error]) {
            return;
        }
    }
    
    if ([fileManager fileExistsAtPath:strSrc]) {
        if ([fileManager copyItemAtURL:movieURL toURL:movieURLD error:&error]) {
            NSLog(@"copied to %@", documentsDirectory);
        }
    }
    
    // make sure you have the AssetsLibrary framework added
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    [library writeVideoAtPathToSavedPhotosAlbum:movieURL
                                completionBlock:^(NSURL *assetURL, NSError *error) {
                                    if (error)
                                        [self showError:error];
                                    else
                                        [self removeFile:movieURL];
                                    
                                    dispatch_async(movieWritingQueue, ^{
                                        recordingWillBeStopped = NO;
                                        self.recording = NO;
                                        
                                        [self.delegate recordingDidStop];
                                    });
                                }];
}

- (void) writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType {
    if ( assetWriter.status == AVAssetWriterStatusUnknown ) {
        
        if ([assetWriter startWriting]) {
            [assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
        }
        else {
            [self showError:[assetWriter error]];
        }
    }
    
    if ( assetWriter.status == AVAssetWriterStatusWriting ) {
        
        if (mediaType == AVMediaTypeVideo) {
            if (assetWriterVideoIn.readyForMoreMediaData) {
                if (![assetWriterVideoIn appendSampleBuffer:sampleBuffer]) {
                    [self showError:[assetWriter error]];
                }
            }
        }
        else if (mediaType == AVMediaTypeAudio) {
            if (assetWriterAudioIn.readyForMoreMediaData) {
                if (![assetWriterAudioIn appendSampleBuffer:sampleBuffer]) {
                    [self showError:[assetWriter error]];
                }
            }
        }
    }
}

#pragma mark  Recording start/stop
- (void) startRecording {
    dispatch_async(movieWritingQueue, ^{
        
        if ( recordingWillBeStarted || self.recording )
            return;
        
        recordingWillBeStarted = YES;
        
        // recordingDidStart is called from captureOutput:didOutputSampleBuffer:fromConnection: once the asset writer is setup
        [self.delegate recordingWillStart];
        
        // Remove the file if one with the same name already exists
        [self removeFile:movieURL];
        
        // Create an asset writer
        [self initAssetWriters];
    });
}

- (void) initAssetWriters {
    
    // Create an asset writer
    NSError *error;
    assetWriter = [[AVAssetWriter alloc] initWithURL:movieURL fileType:(NSString *)kUTTypeQuickTimeMovie error:&error];
    if (error)
        [self showError:error];
}

//TODO: Fix stoprecording

- (void) stopRecording {
    dispatch_async(movieWritingQueue, ^{
        
        if ( recordingWillBeStopped || (self.recording == NO) )
            return;
        
        recordingWillBeStopped = YES;
        
        // recordingDidStop is called from saveMovieToCameraRoll
        [self.delegate recordingWillStop];
        
        recordingWillBeStopped = NO;
        self.recording = NO;
        
        if ([assetWriter finishWriting]) {
            assetWriter = nil;
            
            readyToRecordVideo = NO;
            readyToRecordAudio = NO;
            
            [self saveMovieToCameraRoll];
        }
        else {
            [self showError:[assetWriter error]];
        }
    });
        //[self.delegate recordingDidStop];
        //self.movieURL = [self newMovieURL];
        //[self initAssetWriters];
    //});
    
}


#pragma mark - Setup assetWriters
- (BOOL) setupAssetWriterAudioInput:(CMFormatDescriptionRef)currentFormatDescription {
    const AudioStreamBasicDescription *currentASBD = CMAudioFormatDescriptionGetStreamBasicDescription(currentFormatDescription);
    
    size_t aclSize = 0;
    const AudioChannelLayout *currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(currentFormatDescription, &aclSize);
    NSData *currentChannelLayoutData = nil;
    
    // AVChannelLayoutKey must be specified, but if we don't know any better give an empty data and let AVAssetWriter decide.
    if ( currentChannelLayout && aclSize > 0 )
        currentChannelLayoutData = [NSData dataWithBytes:currentChannelLayout length:aclSize];
    else
        currentChannelLayoutData = [NSData data];
    
    NSDictionary *audioCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                              [NSNumber numberWithInteger:kAudioFormatMPEG4AAC], AVFormatIDKey,
                                              [NSNumber numberWithFloat:currentASBD->mSampleRate], AVSampleRateKey,
                                              [NSNumber numberWithInt:64000], AVEncoderBitRatePerChannelKey,
                                              [NSNumber numberWithInteger:currentASBD->mChannelsPerFrame], AVNumberOfChannelsKey,
                                              currentChannelLayoutData, AVChannelLayoutKey,
                                              nil];
    if ([assetWriter canApplyOutputSettings:audioCompressionSettings forMediaType:AVMediaTypeAudio]) {
        assetWriterAudioIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioCompressionSettings];
        assetWriterAudioIn.expectsMediaDataInRealTime = YES;
        if ([assetWriter canAddInput:assetWriterAudioIn])
            [assetWriter addInput:assetWriterAudioIn];
        else {
            NSLog(@"Couldn't add asset writer audio input.");
            return NO;
        }
    }
    else {
        NSLog(@"Couldn't apply audio output settings.");
        return NO;
    }
    
    return YES;
}

- (BOOL) setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription {
    float bitsPerPixel;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(currentFormatDescription);
    int numPixels = dimensions.width * dimensions.height;
    int bitsPerSecond;
    
    // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
    if ( numPixels < (640 * 480) )
        bitsPerPixel = 4.05; // This bitrate matches the quality produced by AVCaptureSessionPresetMedium or Low.
    else
        bitsPerPixel = 11.4; // This bitrate matches the quality produced by AVCaptureSessionPresetHigh.
    
    bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary *videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                              AVVideoCodecH264, AVVideoCodecKey,
                                              [NSNumber numberWithInteger:dimensions.width], AVVideoWidthKey,
                                              [NSNumber numberWithInteger:dimensions.height], AVVideoHeightKey,
                                              [NSDictionary dictionaryWithObjectsAndKeys:
                                               [NSNumber numberWithInteger:bitsPerSecond], AVVideoAverageBitRateKey,
                                               [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                               nil], AVVideoCompressionPropertiesKey,
                                              nil];
    if ([assetWriter canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo]) {
        assetWriterVideoIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
        assetWriterVideoIn.expectsMediaDataInRealTime = YES;
        assetWriterVideoIn.transform = [self transformFromCurrentVideoOrientationToOrientation:self.referenceOrientation];
        if ([assetWriter canAddInput:assetWriterVideoIn])
            [assetWriter addInput:assetWriterVideoIn];
        else {
            NSLog(@"Couldn't add asset writer video input.");
            return NO;
        }
    }
    else {
        NSLog(@"Couldn't apply video output settings.");
        return NO;
    }
    
    return YES;
}


#pragma mark - Capture

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    if ( connection == videoConnection ) {
        
        // Get framerate
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp( sampleBuffer );
        [self calculateFramerateAtTimestamp:timestamp];
        
        // Get frame dimensions (for onscreen display)
        if (self.videoDimensions.width == 0 && self.videoDimensions.height == 0)
            self.videoDimensions = CMVideoFormatDescriptionGetDimensions( formatDescription );
        
        // Get buffer type
        if ( self.videoType == 0 )
            self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
        
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        /*int bufferWidth = CVPixelBufferGetWidth(pixelBuffer);
        int bufferHeight = CVPixelBufferGetHeight(pixelBuffer);
        unsigned char *pixel = (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
        
        for( int row = 0; row < bufferHeight; row++ ) {
            for( int column = 0; column < bufferWidth; column++ ) {
                pixel[1] = 0; // De-green (second pixel in BGRA is green)
                pixel += 4;
            }
        }*/
        unsigned char *baseaddress= (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
       // void *baseaddress = CVPixelBufferGetBaseAddress(pixelBuffer, 0);
          __block cv::Mat mat((int)CVPixelBufferGetHeight( pixelBuffer ),
         (int)CVPixelBufferGetWidth( pixelBuffer ),
         CV_8UC4,
         baseaddress,
         CVPixelBufferGetBytesPerRow( pixelBuffer ));
        //__block cv::Mat mat;
        dispatch_sync(dispatch_get_main_queue(), ^{
            //cv::GaussianBlur( mat, mat, cv::Size( 7, 7), 0, 0 );
            cv::cvtColor(mat, mat, CV_BGRA2GRAY);
            //cv::cvtColor(mat, mat, CV_RGBA2GRAY);
        });
        //cv::cvtColor(mat, mat, CV_BGRA2GRAY);
        NSLog(@"%d",mat.channels());
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

        //CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        
        
        //unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
       /* void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        size_t width = CVPixelBufferGetWidth( pixelBuffer );
        size_t height = CVPixelBufferGetHeight( pixelBuffer );
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow( pixelBuffer );
        
        
        struct VideoFrame frame;
        
        frame.width = width;
        frame.height = height;
        frame.bytesPerRow = bytesPerRow;
        frame.baseAddress = baseAddress;
        
        [self.delegate renderFrame:frame];*/
        //void *baseaddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
       // size_t width = CVPixelBufferGetWidth( pixelBuffer );
        //size_t height = CVPixelBufferGetHeight( pixelBuffer );
        /*cv::Mat cvMat(CVPixelBufferGetHeight( pixelBuffer ),
                      CVPixelBufferGetWidth( pixelBuffer ),
                      CV_8UC4,
                      baseaddress,
                      0);*/
      // [self.delegate renderMat:cvMat];
        
        
        // For color mode a 4-channel cv::Mat is created from the BGRA data

       // CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        
        //CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        //void *baseaddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        
       // cv::Mat mat(CVPixelBufferGetHeight( pixelBuffer ), CVPixelBufferGetWidth( pixelBuffer ), CV_8UC4, baseaddress, CVPixelBufferGetBytesPerRow( pixelBuffer ));
        
        //[self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        //[self.delegate renderMat:mat];
        //cv::cvtColor(mat, mat, CV_BGRA2GRAY);
        //dispatch_sync(dispatch_get_main_queue(),^{
        //cv::GaussianBlur( mat, mat, cv::Size( 7, 7), 0, 0 );
        //});
        //cv::GaussianBlur( mat, mat, cv::Size( 7, 7), 0, 0 );
        //
        //CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        
        // Enqueue it for preview.  This is a shallow queue, so if image processing is taking too long,
        // we'll drop this frame for preview (this keeps preview latency low).
        OSStatus err = CMBufferQueueEnqueue(previewBufferQueue, sampleBuffer);
        if ( !err ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CMSampleBufferRef sbuf = (CMSampleBufferRef)CMBufferQueueDequeueAndRetain(previewBufferQueue);
                if (sbuf) {
                    CVImageBufferRef pixBuf = CMSampleBufferGetImageBuffer(sbuf);
                    
                    [self.delegate pixelBufferReadyForDisplay:pixBuf];
                    CFRelease(sbuf);
                }
            });
        }
    }
    
    CFRetain(sampleBuffer);
    CFRetain(formatDescription);
    dispatch_async(movieWritingQueue, ^{
        
        if ( assetWriter ) {
            
            BOOL wasReadyToRecord = (readyToRecordAudio && readyToRecordVideo);
            
            if (connection == videoConnection) {
                
                // Initialize the video input if this is not done yet
                if (!readyToRecordVideo)
                    readyToRecordVideo = [self setupAssetWriterVideoInput:formatDescription];
                
                // Write video data to file
                if (readyToRecordVideo && readyToRecordAudio)
                    [self writeSampleBuffer:sampleBuffer ofType:AVMediaTypeVideo];
            }
            else if (connection == audioConnection) {
                
                // Initialize the audio input if this is not done yet
                if (!readyToRecordAudio)
                    readyToRecordAudio = [self setupAssetWriterAudioInput:formatDescription];
                
                // Write audio data to file
                if (readyToRecordAudio && readyToRecordVideo)
                    [self writeSampleBuffer:sampleBuffer ofType:AVMediaTypeAudio];
            }
            
            BOOL isReadyToRecord = (readyToRecordAudio && readyToRecordVideo);
            if ( !wasReadyToRecord && isReadyToRecord ) {
                recordingWillBeStarted = NO;
                self.recording = YES;
                [self.delegate recordingDidStart];
            }
        }
        CFRelease(sampleBuffer);
        CFRelease(formatDescription);
    });
}

#pragma mark Processing
- (void)processPixelBuffer: (CVImageBufferRef)pixelBuffer
{
    
    struct VideoFrame frame = [ImageManager videoFrameFromPixelBuffer:pixelBuffer];
    
    frame = [self.delegate renderFrame:frame];
    
    return;
}


#pragma mark - SetupSession

- (AVCaptureDevice *)videoDeviceWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
        if ([device position] == position)
            return device;
    
    return nil;
}

- (AVCaptureDevice *)audioDevice {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0)
        return [devices objectAtIndex:0];
    
    return nil;
}


- (BOOL) setupCaptureSession {
    /*
     Overview: Uses separate GCD queues for audio and video capture.  If a single GCD queue
     is used to deliver both audio and video buffers, and our video processing consistently takes
     too long, the delivery queue can back up, resulting in audio being dropped.
     
     When recording, it creates a third GCD queue for calls to AVAssetWriter.  This ensures
     that AVAssetWriter is not called to start or finish writing from multiple threads simultaneously.
     
     Uses AVCaptureSession's default preset, AVCaptureSessionPresetHigh.
     */
    
    // Create capture session
    //if (captureSession == nil) {
     //   captureSession = [[AVCaptureSession alloc] init];
    //}
    //else return YES; // have existing session
    captureSession = [[AVCaptureSession alloc] init];
    
    [self setupAudio];
    
    [self setupVideo];
    
    return YES;
}

- (void)setupAudio {

    // Create audio connection
    AVCaptureDeviceInput *audioIn = [[AVCaptureDeviceInput alloc] initWithDevice:[self audioDevice] error:nil];
    if ([captureSession canAddInput:audioIn])
        [captureSession addInput:audioIn];
    
    AVCaptureAudioDataOutput *audioOut = [[AVCaptureAudioDataOutput alloc] init];
    dispatch_queue_t audioCaptureQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
    [audioOut setSampleBufferDelegate:self queue:audioCaptureQueue];
    if ([captureSession canAddOutput:audioOut])
        [captureSession addOutput:audioOut];
    audioConnection = [audioOut connectionWithMediaType:AVMediaTypeAudio];
}

- (void)setupVideo {

    // Create video connection
    AVCaptureDeviceInput *videoIn = [[AVCaptureDeviceInput alloc] initWithDevice:[self videoDeviceWithPosition:AVCaptureDevicePositionBack] error:nil];
    if ([captureSession canAddInput:videoIn])
        [captureSession addInput:videoIn];
    
    int frameRate;
    NSString * preset = AVCaptureSessionPresetHigh;
    if ([[NSProcessInfo processInfo]processorCount]) {
        if ([captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
            preset = AVCaptureSessionPreset640x480;
        }
        frameRate = 20;
    }
    else{
        if ([captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
            preset = AVCaptureSessionPreset1280x720;
        }
        frameRate = 30;
        
    }
    captureSession.sessionPreset = preset;
    
    CMTime frameDuration = kCMTimeInvalid;
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
    _videoCompressionSettings = [[videoOut recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie]
    
    
    AVCaptureVideoDataOutput *videoOut = [[AVCaptureVideoDataOutput alloc] init];
    [videoOut setAlwaysDiscardsLateVideoFrames:NO]; // set this to NO when using AVAssetWriter
    [videoOut setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                           forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    dispatch_queue_t videoCaptureQueue = dispatch_queue_create("Video Capture Queue", DISPATCH_QUEUE_SERIAL);
    
    [videoOut setSampleBufferDelegate:self queue:videoCaptureQueue];
    if ([captureSession canAddOutput:videoOut])
        [captureSession addOutput:videoOut];
    videoConnection = [videoOut connectionWithMediaType:AVMediaTypeVideo];
    self.videoOrientation = [videoConnection videoOrientation];
}

#pragma mark - Lifecycle

- (void) setupAndStartCaptureSession {
    // Create a shallow queue for buffers going to the display for preview.
    OSStatus err = CMBufferQueueCreate(kCFAllocatorDefault, 1, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &previewBufferQueue);
    if (err)
        [self showError:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]];
    
    // Create serial queue for movie writing
    movieWritingQueue = dispatch_queue_create("Movie Writing Queue", DISPATCH_QUEUE_SERIAL);
    
    if ( !captureSession )
        [self setupCaptureSession];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(captureSessionStoppedRunningNotification:) name:AVCaptureSessionDidStopRunningNotification object:captureSession];
    
    if ( !captureSession.isRunning )
        [captureSession startRunning];
}

- (void) pauseCaptureSession {
    if ( captureSession.isRunning )
        [captureSession stopRunning];
}

- (void) resumeCaptureSession {
    if ( !captureSession.isRunning )
        [captureSession startRunning];
}

- (void) stopAndTearDownCaptureSession {
    [captureSession stopRunning];
    if (captureSession)
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionDidStopRunningNotification object:captureSession];
    captureSession = nil;
    if (previewBufferQueue) {
        CFRelease(previewBufferQueue);
        previewBufferQueue = NULL;	
    }
    if (movieWritingQueue) {
        movieWritingQueue = NULL;
    }
}

#pragma mark - Notifications
- (void)captureSessionStoppedRunningNotification:(NSNotification *)notification {
    dispatch_async(movieWritingQueue, ^{
        if ( [self isRecording] ) {
            [self stopRecording];
        }
    });
}

#pragma mark - Error Handling

- (void)showError:(NSError *)error
{
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^(void) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
                                                            message:[error localizedFailureReason]
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
        [alertView show];
    });
}


@end

