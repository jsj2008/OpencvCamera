//
//  CalibrationWrapper.h
//  OpenCV AR
//
//  Created by Anastasia Tarasova on 09/02/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>


@interface CalibrationWrapper : NSObject



- (void) calibrateWithImageArray:(NSArray*)images;

-(void) drawCheccBoardCornersOnFrame:(cv::Mat&)cvMat;



@end
