//
//  AVUtils.h
//  RenderCamera
//
//  Created by Anastasia Tarasova on 16/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

@interface AVFoundationUtils : NSObject

+ (AVCaptureVideoOrientation)videoOrientationFromDeviceOrientation:(UIDeviceOrientation)deviceOrientation;
+ (AVCaptureVideoOrientation)videoOrientationFromInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;

@end
