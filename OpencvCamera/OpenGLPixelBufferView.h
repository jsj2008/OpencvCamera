//
//  OpenGLPixelBufferView.h
//  OpencvCamera
//
//  Created by Anastasia Tarasova on 16/05/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <CoreVideo/CoreVideo.h>

@protocol OpenGLShaderFilter;

@interface OpenGLPixelBufferView : UIView

@property (nonatomic, retain) id<OpenGLShaderFilter> filter;

- (void)displayImage:(UIImage *)image;
- (void)displayViewContent:(UIView *)view;
- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)flushPixelBufferCache;
- (void)reset;

@property (nonatomic) BOOL mirrorTransform;

@end