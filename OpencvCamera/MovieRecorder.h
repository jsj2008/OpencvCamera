//
//  MovieRecorder.h
//  OpencvCamera
//
//  Created by Anastasia Tarasova on 16/05/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <CoreMedia/CMFormatDescription.h>
#import <CoreMedia/CMSampleBuffer.h>

@protocol MovieRecorderDelegate;

@interface MovieRecorder : NSObject

- (instancetype)initWithURL:(NSURL *)URL;

// Only one audio and video track each are allowed.
- (void)addVideoTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription transform:(CGAffineTransform)transform settings:(NSDictionary *)videoSettings; // see AVVideoSettings.h for settings keys/values
- (void)addAudioTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)audioSettings; // see AVAudioSettings.h for settings keys/values

- (void)setDelegate:(id<MovieRecorderDelegate>)delegate callbackQueue:(dispatch_queue_t)delegateCallbackQueue; // delegate is weak referenced

- (void)prepareToRecord; // Asynchronous, might take several hundred milliseconds. When finished the delegate's recorderDidFinishPreparing: or recorder:didFailWithError: method will be called.

- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)appendVideoPixelBuffer:(CVPixelBufferRef)pixelBuffer withPresentationTime:(CMTime)presentationTime;
- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)finishRecording; // Asynchronous, might take several hundred milliseconds. When finished the delegate's recorderDidFinishRecording: or recorder:didFailWithError: method will be called.

@end

@protocol MovieRecorderDelegate <NSObject>
@required
- (void)movieRecorderDidFinishPreparing:(MovieRecorder *)recorder;
- (void)movieRecorder:(MovieRecorder *)recorder didFailWithError:(NSError *)error;
- (void)movieRecorderDidFinishRecording:(MovieRecorder *)recorder;
@end

