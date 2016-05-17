//
//  ImageManager.h
//  OpenCV AR
//
//  Created by Anastasia Tarasova on 15/02/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <opencv2/opencv.hpp>
#import "VideoFrame.h"



@interface ImageManager : NSObject

+(VideoFrame)videoFrameFromPixelBuffer:(CVPixelBufferRef)pixelBuffer;
+(cv::Mat)cvMatFromVideoFrame:(VideoFrame)frame;
+(CGImageRef)cgImageFromMat:(cv::Mat)cvMat;


+ (cv::Mat ) createMatFromImageBuffer:(CVImageBufferRef) imageBuffer;
//+ (CVPixelBufferRef) createPixelBufferFromMat:(cv::Mat)mat;
+ (CMSampleBufferRef)sampleBufferFromCGImage:(CGImageRef)image;
+ (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image;
+ (CMSampleBufferRef)sampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer;


@end
