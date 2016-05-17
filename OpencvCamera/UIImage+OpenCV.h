//
//  UIImage+OpenCV.h
//  OpenCV AR
//
//  Created by Anastasia Tarasova on 06/02/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <opencv2/opencv.hpp>

@interface UIImage (OpenCV)

//cv::Mat to UIImage
+ (UIImage *)imageWithCVMat:(const cv::Mat&)cvMat;
- (id)initWithCVMat:(const cv::Mat&)cvMat;

//UIImage to cv::Mat
- (cv::Mat)CVMat;
- (cv::Mat)CVMat3;
- (cv::Mat)CVGrayScaleMat;

@end
