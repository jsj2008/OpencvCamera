//
//  CapturePipeline.h
//  OpencvCamera
//
//  Created by Anastasia Tarasova on 16/05/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

// Based on the RosyWriter sample code


#import <AVFoundation/AVFoundation.h>

@protocol CapturePipelineDelegate;

@interface CapturePipeline : NSObject

- (void)setDelegate:(id<CapturePipelineDelegate>)delegate callbackQueue:(dispatch_queue_t)delegateCallbackQueue; // delegate is weak referenced

// These methods are synchronous
- (void)startRunning;
- (void)stopRunning;

// Must be running before starting recording
// These methods are asynchronous, see the recording delegate callbacks
- (void)startRecording;
- (void)stopRecording;

@property(readwrite) BOOL renderingEnabled; // When set to false the GPU will not be used after the setRenderingEnabled: call returns.

@property(readwrite) AVCaptureVideoOrientation recordingOrientation; // client can set the orientation for the recorded movie

- (CGAffineTransform)transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)orientation withAutoMirroring:(BOOL)mirroring; // only valid after startRunning has been called

// Stats
@property(readonly) float videoFrameRate;
@property(readonly) CMVideoDimensions videoDimensions;

- (BOOL)toggleInputDevice;

@end

@protocol CapturePipelineDelegate <NSObject>
@required

- (void)capturePipeline:(CapturePipeline *)capturePipeline didStartRunningWithVideoDevice:(AVCaptureDevice *)videoDevice;
-(CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)capturePipeline:(CapturePipeline *)capturePipeline didStopRunningWithError:(NSError *)error;

// Preview
- (void)capturePipeline:(CapturePipeline *)capturePipeline previewPixelBufferReadyForDisplay:(CVPixelBufferRef)previewPixelBuffer;
- (void)capturePipelineDidRunOutOfPreviewBuffers:(CapturePipeline *)capturePipeline;

// Recording
- (void)capturePipelineRecordingDidStart:(CapturePipeline *)capturePipeline;
- (void)capturePipeline:(CapturePipeline *)capturePipeline recordingDidFailWithError:(NSError *)error; // Can happen at any point after a startRecording call, for example: startRecording->didFail (without a didStart), willStop->didFail (without a didStop)
- (void)capturePipelineRecordingWillStop:(CapturePipeline *)capturePipeline;
- (void)capturePipelineRecordingDidStop:(CapturePipeline *)capturePipeline;

@end

