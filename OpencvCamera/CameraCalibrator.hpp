//
//  CameraCalibrator.hpp
//  OpenCV AR
//
//  Created by Anastasia Tarasova on 09/02/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//



#include <stdio.h>
#include <opencv2/opencv.hpp>

using namespace std;

class CameraCalibrator {
    
public:
    CameraCalibrator() : flag(0), mustInitUndistort(true) {};
    
    int addChessboardPoints(vector<cv::Mat> &images, cv::Size &boardSize);
    
    void getCameraMatrixAndDistCoeffMatrix(cv::Mat &outputCameraMatrix, cv::Mat &outputDistCoeffMatrix);
    double calibrate(cv::Size &imageSize);
    
    /// check frame for recognized pattern
    cv::Mat drawBoardCorners(cv::Mat &image, cv::Size &boardSize);
    // remove distortion in an image (after calibration)
    cv::Mat remap(const cv::Mat &image);
    
#pragma mark - Set functions
    
    /// set chessboard's width and height
    void setChessBoardSize(int width, int height){
        
        bSize.width = width;
        bSize.height = height;
    }
    cv::Size getChessboardSize(){
        return bSize;
    }
    
    /// set required frames number for successful
    void setRequiredFramesNumber(int frames){
        if (frames >3){
            framesRequired = frames;
        }
    }
    int getRequiredFramesNumber(){
        return framesRequired;
    }
    
private:
    // input points
    vector<vector<cv::Point3f>> objectPoints;
    vector<vector<cv::Point2f>> imagePoints;
    
    // output Matrices
    cv::Mat cameraMatrix;
    cv::Mat distCoeffs;
    
    // flag to specify how calibration is done
    int flag;
    
    // used in image undistortion
    cv::Mat map1, map2;
    bool mustInitUndistort;
    
#pragma mark - Private methods
    void addPoints(const vector<cv::Point2f> &imageCorners, const vector<cv::Point3f> &objectCorners);
    
    bool findBoardPoints(cv::Mat &image, cv::Size & boardSize,vector<cv::Point2f> &imageCorners,
                             vector<cv::Point3f> &objectCorners);

    
    //MARK: - Parameters
    cv::Size bSize;
    
    //In practice, 10 to 20 chessboard images are sufficient, but these must be taken from different viewpoints at different depths
    int framesRequired = 10;
    // how much frames are being given to calibrator
    int framesProcessing;
    
};
