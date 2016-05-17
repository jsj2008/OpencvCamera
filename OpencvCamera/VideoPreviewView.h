//
//  VideoPreviewView.h
//  RenderCamera
//
//  Created by Anastasia Tarasova on 14/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES2/glext.h>
#import <CoreVideo/CVOpenGLESTextureCache.h>

#import <AVFoundation/AVFoundation.h>

@interface VideoPreviewView : UIView{

    int renderBufferWidth;
    int renderBufferHeight;
    
    CVOpenGLESTextureCacheRef videoTextureCache;
    
    EAGLContext* oglContext;
    GLuint frameBufferHandle;
    GLuint colorBufferHandle;
    GLuint passThroughProgram;
    
    CALayer *customPreviewLayer;
}

@property (nonatomic, strong) CALayer *customPreviewLayer;

- (void)displayPixelBuffer:(CVImageBufferRef)pixelBuffer;

@end
