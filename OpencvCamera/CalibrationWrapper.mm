//
//  CalibrationWrapper.m
//  OpenCV AR
//
//  Created by Anastasia Tarasova on 09/02/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//


#import "CalibrationWrapper.h"
#import "CameraCalibrator.hpp"
#import "UIImage+OpenCV.h"
#import "ImageManager.h"
//#import <opencv2/imgcodecs/ios.h>



@interface CalibrationWrapper()

@property (nonatomic) CameraCalibrator * calibrator;

@end

@implementation CalibrationWrapper

@synthesize calibrator = _calibrator;


-(id)init {
    if ( self = [super init] ) {
        _calibrator = new CameraCalibrator();
    }
    return self;
}

- (void) calibrateWithImageArray:(NSArray *)images {
    
    std::vector<cv::Mat> imageVector;
    for (int i = 0; i < images.count; i++) {
        UIImage *image = images[i];
        cv::Mat imageMatrix = image.CVMat3;
        imageVector.push_back(imageMatrix);
        std::cout << "Loading image matrix: " << i << std::endl;
    }
    std::cout << "Done loading image matrix" << std::endl;
    cv::Size boardSize;
    //specifiy the board size - 1
    //for example, if you has a chessboard with 8*8 grid, put 7 for height and width here.
    boardSize.height = 7;
    boardSize.width = 7;
    self.calibrator->addChessboardPoints(imageVector, boardSize);
    cv::Size imageSize = imageVector[0].size();
    double error = self.calibrator->calibrate(imageSize);
    std::cout << "Done calibration, error: " << error << std::endl;
    
    cv::Mat cameraMatrix, distMatrix;
    self.calibrator->getCameraMatrixAndDistCoeffMatrix(cameraMatrix, distMatrix);
    cout << "Camera Matrix: \n" << cameraMatrix << endl << endl;
    cout << "Dist Matrix: \n" << distMatrix << endl << endl;
}

-(void) drawCheccBoardCornersOnFrame:(cv::Mat&)cvMat
{
 /*   int bufferWidth = CVPixelBufferGetWidth(pixelBuffer);
    int bufferHeight = CVPixelBufferGetHeight(pixelBuffer);
    unsigned char *pixel = (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
    
    for( int row = 0; row < bufferHeight; row++ ) {
        for( int column = 0; column < bufferWidth; column++ ) {
            pixel[1] = 0; // De-green (second pixel in BGRA is green)
            pixel += 4;
        }
    }*/
    //cv::Mat bgraFrame = [ImageManager createMatFromImageBuffer:pixelBuffer];
    
    cv::Size boardSize;
    boardSize.height = 7;
    boardSize.width = 7;
    
    
    //cv::Mat image;
    
    cvMat = _calibrator->drawBoardCorners(cvMat, boardSize);
    
    /*(for( int row = 0; row < image.rows; row++ ) {
        for( int column = 0; column < image.cols; column++ ) {
            if( row== column){
            image.at<uchar>(row,column) = 0; // De-green (second pixel in BGRA is green)
            //pixel += 4;
            }
        }
    }*/
    
    //CGImageRef dstImage = [ImageManager cgImageFromMat:cvMat];
    //return dstImage;
}
@end

