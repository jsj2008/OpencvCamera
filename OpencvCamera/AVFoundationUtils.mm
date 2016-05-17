//
//  AVUtils.m
//  RenderCamera
//
//  Created by Anastasia Tarasova on 16/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import "AVFoundationUtils.h"

@implementation AVFoundationUtils

+ (AVCaptureVideoOrientation)videoOrientationFromDeviceOrientation:(UIDeviceOrientation)deviceOrientation{

    AVCaptureVideoOrientation orientation;
    switch (deviceOrientation) {
        case UIDeviceOrientationUnknown:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationPortrait:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIDeviceOrientationLandscapeLeft:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIDeviceOrientationLandscapeRight:
            orientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationFaceUp:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationFaceDown:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
    }
    return orientation;
}

+ (AVCaptureVideoOrientation)videoOrientationFromInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation{

    AVCaptureVideoOrientation orientation;
    switch (interfaceOrientation) {
        case UIInterfaceOrientationUnknown:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationPortrait:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            orientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        }
    return orientation;
    
}

@end
