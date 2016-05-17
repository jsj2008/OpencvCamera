//
//  VisualizationEngine.h
//  OpencvCamera
//
//  Created by Anastasia Tarasova on 17/05/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <Foundation/Foundation.h>

////////////////////////////////////////////////////////////////////
// File includes:
#import "EAGLView.h"
#import "VideoFrame.h"

@interface VisualizationEngine : NSObject
{
    EAGLView * m_glview;
    GLuint m_backgroundTextureId;
    //std::vector<Transformation> m_transformations;
    //CameraCalibration m_calibration;
    CGSize m_frameSize;
}

-(id) initWithGLView:(EAGLView*)view frameSize:(CGSize) size;

-(void) drawFrame;
-(void) updateBackground:(VideoFrame) frame;
//-(void) setTransformationList:(const std::vector<Transformation>&) transformations;

@end
