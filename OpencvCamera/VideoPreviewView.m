//
//  VideoPreviewView.m
//  RenderCamera
//
//  Created by Anastasia Tarasova on 14/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <QuartzCore/CAEAGLLayer.h>
#import "VideoPreviewView.h"
#include "ShaderUtilities.h"

enum {
    ATTRIB_VERTEX,
    ATTRIB_TEXTUREPOSITON,
    NUM_ATTRIBUTES
};

@implementation VideoPreviewView

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (const GLchar *)readFile:(NSString *)name
{
    NSString *path;
    const GLchar *source;
    
    path = [[NSBundle mainBundle] pathForResource:name ofType: nil];
    source = (GLchar *)[[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] UTF8String];
    
    return source;
}

- (BOOL)initializeBuffers
{
    BOOL success = YES;
    
    glDisable(GL_DEPTH_TEST);
    
    glGenFramebuffers(1, &frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, frameBufferHandle);
    
    glGenRenderbuffers(1, &colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, colorBufferHandle);
    
    [oglContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &renderBufferWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &renderBufferHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorBufferHandle);
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failure with framebuffer generation");
        success = NO;
    }
    
    //  Create a new CVOpenGLESTexture cache
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge CVEAGLContext _Nonnull)((__bridge void*)oglContext), NULL, &videoTextureCache);
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        success = NO;
    }
    
    // Load vertex and fragment shaders
    const GLchar *vertSrc = [self readFile:@"passThrough.vsh"];
    const GLchar *fragSrc = [self readFile:@"passThrough.fsh"];
    
    // attributes
    GLint attribLocation[NUM_ATTRIBUTES] = {
        ATTRIB_VERTEX, ATTRIB_TEXTUREPOSITON,
    };
    GLchar *attribName[NUM_ATTRIBUTES] = {
        "position", "textureCoordinate",
    };
    
    glueCreateProgram(vertSrc, fragSrc,
                      NUM_ATTRIBUTES, (const GLchar **)&attribName[0], attribLocation,
                      0, 0, 0, // we don't need to get uniform locations in this example
                      &passThroughProgram);
    
    if (!passThroughProgram)
        success = NO;
    
    return success;
}

-(id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        // Use 2x scale factor on Retina displays.
        self.contentScaleFactor = [[UIScreen mainScreen] scale];
        
        // Initialize OpenGL ES 2
        CAEAGLLayer* eaglLayer = (CAEAGLLayer *)self.layer;
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking,
                                        kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                        nil];
        oglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!oglContext || ![EAGLContext setCurrentContext:oglContext]) {
            NSLog(@"Problem with OpenGL context.");
            
            return nil;
        }
        
        // create a custom preview layer
       // self.customPreviewLayer = [CALayer layer];
       //self.customPreviewLayer.bounds = CGRectMake(0, 0, self.parentView.frame.size.width, self.parentView.frame.size.height);
        //[self layoutPreviewLayer];
        
        
    }
    
    return self;
}

- (void)createCustomVideoPreview;
{
    [self.layer addSublayer:self.customPreviewLayer];
}



- (void)renderWithSquareVertices:(const GLfloat*)squareVertices textureVertices:(const GLfloat*)textureVertices
{
    // Use shader program.
    glUseProgram(passThroughProgram);
    
    // Update attribute values.
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, squareVertices);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices);
    glEnableVertexAttribArray(ATTRIB_TEXTUREPOSITON);
    
    // Update uniform values if there are any
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    // Present
    glBindRenderbuffer(GL_RENDERBUFFER, colorBufferHandle);
    [oglContext presentRenderbuffer:GL_RENDERBUFFER];
}

- (CGRect)textureSamplingRectForCroppingTextureWithAspectRatio:(CGSize)textureAspectRatio toAspectRatio:(CGSize)croppingAspectRatio
{
    CGRect normalizedSamplingRect = CGRectZero;
    CGSize cropScaleAmount = CGSizeMake(croppingAspectRatio.width / textureAspectRatio.width, croppingAspectRatio.height / textureAspectRatio.height);
    CGFloat maxScale = fmax(cropScaleAmount.width, cropScaleAmount.height);
    CGSize scaledTextureSize = CGSizeMake(textureAspectRatio.width * maxScale, textureAspectRatio.height * maxScale);
    
    if ( cropScaleAmount.height > cropScaleAmount.width ) {
        normalizedSamplingRect.size.width = croppingAspectRatio.width / scaledTextureSize.width;
        normalizedSamplingRect.size.height = 1.0;
    }
    else {
        normalizedSamplingRect.size.height = croppingAspectRatio.height / scaledTextureSize.height;
        normalizedSamplingRect.size.width = 1.0;
    }
    // Center crop
    normalizedSamplingRect.origin.x = (1.0 - normalizedSamplingRect.size.width)/2.0;
    normalizedSamplingRect.origin.y = (1.0 - normalizedSamplingRect.size.height)/2.0;
    
    return normalizedSamplingRect;
}

- (void)displayPixelBuffer:(CVImageBufferRef)pixelBuffer
{
    if (frameBufferHandle == 0) {
        BOOL success = [self initializeBuffers];
        if ( !success ) {
            NSLog(@"Problem initializing OpenGL buffers.");
        }
    }
    
    if (videoTextureCache == NULL)
        return;
    
    // Create a CVOpenGLESTexture from the CVImageBuffer
    size_t frameWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t frameHeight = CVPixelBufferGetHeight(pixelBuffer);
    CVOpenGLESTextureRef texture = NULL;
    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                videoTextureCache,
                                                                pixelBuffer,
                                                                NULL,
                                                                GL_TEXTURE_2D,
                                                                GL_RGBA,
                                                                frameWidth,
                                                                frameHeight,
                                                                GL_BGRA,
                                                                GL_UNSIGNED_BYTE,
                                                                0,
                                                                &texture);
    
    
    if (!texture || err) {
        NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
        return;
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(texture), CVOpenGLESTextureGetName(texture));
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindFramebuffer(GL_FRAMEBUFFER, frameBufferHandle);
    
    // Set the view port to the entire view
    glViewport(0, 0, renderBufferWidth, renderBufferHeight);
    
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    // The texture vertices are set up such that we flip the texture vertically.
    // This is so that our top left origin buffers match OpenGL's bottom left texture coordinate system.
    CGRect textureSamplingRect = [self textureSamplingRectForCroppingTextureWithAspectRatio:CGSizeMake(frameWidth, frameHeight) toAspectRatio:self.bounds.size];
    GLfloat textureVertices[] = {
        CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
    };
    
    // Draw the texture on the screen with OpenGL ES 2
    [self renderWithSquareVertices:squareVertices textureVertices:textureVertices];
    
    glBindTexture(CVOpenGLESTextureGetTarget(texture), 0);
    
    // Flush the CVOpenGLESTexture cache and release the texture
    CVOpenGLESTextureCacheFlush(videoTextureCache, 0);
    CFRelease(texture);
}

#pragma mark - Dealloc

- (void)dealloc
{
    if (frameBufferHandle) {
        glDeleteFramebuffers(1, &frameBufferHandle);
        frameBufferHandle = 0;
    }
    
    if (colorBufferHandle) {
        glDeleteRenderbuffers(1, &colorBufferHandle);
        colorBufferHandle = 0;
    }
    
    if (passThroughProgram) {
        glDeleteProgram(passThroughProgram);
        passThroughProgram = 0;
    }
    
    if (videoTextureCache) {
        CFRelease(videoTextureCache);
        videoTextureCache = 0;
    }
    
}
/*
 - (void)adjustLayoutToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
 {
 
 NSLog(@"layout preview layer");
 if (self.parentView != nil) {
 
 CALayer* layer = self.customPreviewLayer;
 CGRect bounds = self.customPreviewLayer.bounds;
 int rotation_angle = 0;
 bool flip_bounds = false;
 
 switch (interfaceOrientation) {
 case UIInterfaceOrientationPortrait:
 NSLog(@"to Portrait");
 rotation_angle = 270;
 break;
 case UIInterfaceOrientationPortraitUpsideDown:
 rotation_angle = 90;
 NSLog(@"to UpsideDown");
 break;
 case UIInterfaceOrientationLandscapeLeft:
 rotation_angle = 0;
 NSLog(@"to LandscapeLeft");
 break;
 case UIInterfaceOrientationLandscapeRight:
 rotation_angle = 180;
 NSLog(@"to LandscapeRight");
 break;
 default:
 break; // leave the layer in its last known orientation
 }
 
 switch (defaultAVCaptureVideoOrientation) {
 case AVCaptureVideoOrientationLandscapeRight:
 rotation_angle += 180;
 break;
 case AVCaptureVideoOrientationPortraitUpsideDown:
 rotation_angle += 270;
 break;
 case AVCaptureVideoOrientationPortrait:
 rotation_angle += 90;
 case AVCaptureVideoOrientationLandscapeLeft:
 break;
 default:
 break;
 }
 rotation_angle = rotation_angle % 360;
 
 if (rotation_angle == 90 || rotation_angle == 270) {
 flip_bounds = true;
 }
 
 if (flip_bounds) {
 NSLog(@"flip bounds");
 bounds = CGRectMake(0, 0, bounds.size.height, bounds.size.width);
 }
 
 layer.position = CGPointMake(self.parentView.frame.size.width/2., self.parentView.frame.size.height/2.);
 self.customPreviewLayer.bounds = CGRectMake(0, 0, self.parentView.frame.size.width, self.parentView.frame.size.height);
 
 layer.affineTransform = CGAffineTransformMakeRotation( DegreesToRadians(rotation_angle) );
 layer.bounds = bounds;
 }
 
 }
 
 // TODO fix
 - (void)layoutPreviewLayer;
 {
 NSLog(@"layout preview layer");
 if (self.parentView != nil) {
 
 CALayer* layer = self.customPreviewLayer;
 CGRect bounds = self.customPreviewLayer.bounds;
 int rotation_angle = 0;
 bool flip_bounds = false;
 
 switch (currentDeviceOrientation) {
 case UIDeviceOrientationPortrait:
 rotation_angle = 270;
 break;
 case UIDeviceOrientationPortraitUpsideDown:
 rotation_angle = 90;
 break;
 case UIDeviceOrientationLandscapeLeft:
 NSLog(@"left");
 rotation_angle = 180;
 break;
 case UIDeviceOrientationLandscapeRight:
 NSLog(@"right");
 rotation_angle = 0;
 break;
 case UIDeviceOrientationFaceUp:
 case UIDeviceOrientationFaceDown:
 default:
 break; // leave the layer in its last known orientation
 }
 
 switch (defaultAVCaptureVideoOrientation) {
 case AVCaptureVideoOrientationLandscapeRight:
 rotation_angle += 180;
 break;
 case AVCaptureVideoOrientationPortraitUpsideDown:
 rotation_angle += 270;
 break;
 case AVCaptureVideoOrientationPortrait:
 rotation_angle += 90;
 case AVCaptureVideoOrientationLandscapeLeft:
 break;
 default:
 break;
 }
 rotation_angle = rotation_angle % 360;
 
 if (rotation_angle == 90 || rotation_angle == 270) {
 flip_bounds = true;
 }
 
 if (flip_bounds) {
 NSLog(@"flip bounds");
 bounds = CGRectMake(0, 0, bounds.size.height, bounds.size.width);
 }
 
 layer.position = CGPointMake(self.parentView.frame.size.width/2., self.parentView.frame.size.height/2.);
 layer.affineTransform = CGAffineTransformMakeRotation( DegreesToRadians(rotation_angle) );
 layer.bounds = bounds;
 }
 
 }

 */

@end
