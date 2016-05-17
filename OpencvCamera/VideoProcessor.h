//
//  VideoProcessor.h
//  RenderCamera
//
//  Created by Anastasia Tarasova on 12/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

// Based on Apple's RosyWriter example project

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CMBufferQueue.h>
#import <CoreGraphics/CoreGraphics.h>
#import "VideoFrame.h"

@protocol VideoProcessorDelegate;

@interface VideoProcessor : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
{
    __weak id <VideoProcessorDelegate> delegate;
    
    NSMutableArray *previousSecondTimestamps;
    Float64 videoFrameRate;
    CMVideoDimensions videoDimensions;
    CMVideoCodecType videoType;
    
    AVCaptureSession *captureSession;
    AVCaptureConnection *audioConnection;
    AVCaptureConnection *videoConnection;
    CMBufferQueueRef previewBufferQueue;
    
    AVCaptureDevice * videoDevice;
    AVCaptureDevice * audioDevice;
    
    NSURL *movieURL;
    
    AVAssetWriter *assetWriter;
    AVAssetWriterInput *assetWriterAudioIn;
    AVAssetWriterInput *assetWriterVideoIn;
    dispatch_queue_t movieWritingQueue;
    
    CMFormatDescriptionRef videoFormatDescription;
    CMFormatDescriptionRef audioFormatDescription;
    
    AVCaptureVideoOrientation referenceOrientation;
    AVCaptureVideoOrientation videoOrientation;
    
    // Only accessed on movie writing queue
    BOOL readyToRecordAudio;
    BOOL readyToRecordVideo;
    BOOL recordingWillBeStarted;
    BOOL recordingWillBeStopped;
    
    BOOL recording;
}

@property (weak) id <VideoProcessorDelegate> delegate;

@property (readonly) Float64 videoFrameRate;
@property (readonly) CMVideoDimensions videoDimensions;
@property (readonly) CMVideoCodecType videoType;

@property (nonatomic) AVCaptureVideoOrientation referenceOrientation;

- (CGAffineTransform)transformFromCurrentVideoOrientationToOrientation:(AVCaptureVideoOrientation)orientation;

- (CGAffineTransform)transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)orientation withAutoMirroring:(BOOL)mirroring;

- (void) showError:(NSError*)error;

- (void) setupAndStartCaptureSession;
- (void) stopAndTearDownCaptureSession;

- (void) startRecording;
- (void) stopRecording;

- (void) pauseCaptureSession; // Pausing while a recording is in progress will cause the recording to be stopped and saved.
- (void) resumeCaptureSession;
- (void) swapFrontAndBackCameras;

@property(readonly, getter=isRecording) BOOL recording;

@property(readwrite) BOOL renderingEnabled;

@end


#pragma mark - VideoProcessorDelegate
@protocol VideoProcessorDelegate <NSObject>
@required
- (void)pixelBufferReadyForDisplay:(CVPixelBufferRef)pixelBuffer;	// This method is always called on the main thread.
- (CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (VideoFrame)renderFrame:(VideoFrame)frame;
- (void)renderMat:(cv::Mat &)cvMat;

- (void)recordingWillStart;
- (void)recordingDidStart;
- (void)recordingWillStop;
- (void)recordingDidStop;

//- (void)capturePipelineDidRunOutOfPreviewBuffers:(CapturePipeline *)capturePipeline;

//- (void)changeImage:(int)nType imageSrc:(UIImage*)currentImage;
//- (void)imageBufferReadyForDisplay:(UIImage*)pixelBuffer;


@end
