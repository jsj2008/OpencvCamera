//
//  ViewController.m
//  RenderCamera
//
//  Created by Anastasia Tarasova on 12/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import "ARViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "CalibrationWrapper.h"
#import "AVFoundationUtils.h"
#import "ImageManager.h"
#import "VideoFrame.h"

#import "CameraCalibrator.hpp"

static inline double radians (double degrees) { return degrees * (M_PI / 180); }

@interface ARViewController()

@property(strong,nonatomic)CalibrationWrapper* calibrator;

@property (nonatomic) CameraCalibrator * cameraCalibrator;
@end

@implementation ARViewController

@synthesize recordButton;
@synthesize calibrator;

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)applicationDidBecomeActive:(NSNotification*)notifcation
{
    // For performance reasons, we manually pause/resume the session when saving a recording.
    // If we try to resume the session in the background it will fail. Resume the session here as well to ensure we will succeed.
    [videoProcessor resumeCaptureSession];
}


- (void)deviceOrientationDidChange
{
   /* UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    // Don't update the reference orientation when the device orientation is face up/down or unknown.
    if ( UIDeviceOrientationIsPortrait(orientation) || UIDeviceOrientationIsLandscape(orientation) ){
        AVCaptureVideoOrientation videoOrientation = [AVFoundationUtils videoOrientationFromDeviceOrientation:orientation];
        [videoProcessor setReferenceOrientation: videoOrientation];
        
    }*/
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    calibrator = [[CalibrationWrapper alloc ] init];
    // Initialize the class responsible for managing AV capture session and asset writer
    videoProcessor = [[VideoProcessor alloc] init];
    videoProcessor.delegate = self;
    
    // Keep track of changes to the device orientation so we can update the video processor
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(deviceOrientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
       
    // Setup and start the capture session
    [videoProcessor setupAndStartCaptureSession];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
    
    NSLog(@" viewDidLoad: %@ ",self.view);
    
    dispatch_async(dispatch_get_main_queue(),^{
        [self setupPreviewView];
    });
    
    

}

-(void)setupPreviewView{

    previewView = [[VideoPreviewView alloc] initWithFrame:CGRectZero];
    //previewView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

    UIInterfaceOrientation statusBarOrientation = [[UIApplication sharedApplication]statusBarOrientation];
    AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
    
    if (statusBarOrientation != UIInterfaceOrientationUnknown) {
        initialVideoOrientation = [AVFoundationUtils videoOrientationFromInterfaceOrientation:statusBarOrientation];
    }
    
    previewView.transform = [videoProcessor transformFromCurrentVideoOrientationToOrientation:initialVideoOrientation];
    CGRect bounds = CGRectZero;
    bounds.size = [self.view convertRect:self.view.bounds toView:previewView].size;
    previewView.frame = CGRectMake(0,0,self.view.bounds.size.width,self.view.bounds.size.height);//bounds;
    previewView.center = CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0);
    previewView.contentScaleFactor = [[UIScreen mainScreen] scale];

   // [self.view addSubview:previewView];
    [self.view insertSubview:previewView atIndex:0];

}


// Technical Q&A QA1890
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
 
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        
        CGAffineTransform deltaTransform = coordinator.targetTransform;
        CGFloat deltaAngle = atan2f(deltaTransform.b, deltaTransform.a);
        
        CGFloat currentRotation = [[previewView.layer valueForKeyPath:@"transform.rotation.z"] floatValue];
        // Adding a small value to the rotation angle forces the animation to occur in a the desired direction, preventing an issue where the view would appear to rotate 2PI radians during a rotation from LandscapeRight -> LandscapeLeft.
        currentRotation += -1 * deltaAngle + 0.0001;
        [previewView.layer setValue:@(currentRotation) forKeyPath:@"transform.rotation.z"];
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        
        // after rotation
        CGAffineTransform currentTransform = previewView.transform;
        currentTransform.a = round(currentTransform.a);
        currentTransform.b = round(currentTransform.b);
        currentTransform.c = round(currentTransform.c);
        currentTransform.d = round(currentTransform.d);
        
        previewView.transform = currentTransform;
        
    }];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    previewView.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
}


- (void)cleanup
{
    previewView = nil;
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    
    [notificationCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
    
    // Stop and tear down the capture session
    [videoProcessor stopAndTearDownCaptureSession];
    videoProcessor.delegate = nil;
}

- (void)viewDidUnload
{
    [self setRecordButton:nil];
    [super viewDidUnload];
    [self cleanup];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    NSLog(@"viewWillAppear: %@",self.view);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    //[self deviceOrientationDidChange];
    // Return YES for supported orientations
    return YES;
}

- (IBAction)toggleRecording:(id)sender
{
    // Wait for the recording to start/stop before re-enabling the record button.
    [[self recordButton] setEnabled:NO];
    
    if ( [videoProcessor isRecording] ) {
        // The recordingWill/DidStop delegate methods will fire asynchronously in response to this call
        [videoProcessor stopRecording];
    }
    else {
        // The recordingWill/DidStart delegate methods will fire asynchronously in response to this call
        [videoProcessor startRecording];
    }
}

#pragma mark RosyWriterVideoProcessorDelegate

- (void)recordingWillStart
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self recordButton] setEnabled:NO];
        [[self recordButton] setTitle:@"Stop" forState:UIControlStateNormal];
        
        // Disable the idle timer while we are recording
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        
        // Make sure we have time to finish saving the movie if the app is backgrounded during recording
        if ([[UIDevice currentDevice] isMultitaskingSupported])
            backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
    });
}

- (void)recordingDidStart
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self recordButton] setEnabled:YES];
    });
}

- (void)recordingWillStop
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Disable until saving to the camera roll is complete
        [[self recordButton] setTitle:@"Record" forState:UIControlStateNormal];
        [[self recordButton] setEnabled:NO];
        
        // Pause the capture session so that saving will be as fast as possible.
        // We resume the sesssion in recordingDidStop:
        [videoProcessor pauseCaptureSession];
    });
}

- (void)recordingDidStop {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self recordButton] setEnabled:YES];
        
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        [videoProcessor resumeCaptureSession];
        
        if ([[UIDevice currentDevice] isMultitaskingSupported]) {
            [[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
            backgroundRecordingID = UIBackgroundTaskInvalid;
        }
    });
}

#pragma mark - PixelBuffer work
- (void)pixelBufferReadyForDisplay:(CVPixelBufferRef)pixelBuffer {
    // Don't make OpenGLES calls while in the background.
        if ( [UIApplication sharedApplication].applicationState != UIApplicationStateBackground )
            [previewView displayPixelBuffer:pixelBuffer];
}

- (CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer{

    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    //__block CGImageRef dstImage;
    //dispatch_sync(dispatch_get_main_queue(), ^{
    
   // dstImage = [self.calibrator drawCheccBoardCornersOnFrame:pixelBuffer];
   // });
    //CGImageRef dstImage = [self.calibrator drawCheccBoardCornersOnFrame:pixelBuffer];
   // return dstImage;
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t stride = CVPixelBufferGetBytesPerRow( pixelBuffer );
    size_t extendedWidth = stride / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits
    
    cv::Mat image = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    //cv::Mat image = [ImageManager createMatFromImageBuffer:pixelBuffer];
    
    //cv::Mat image = cv::imread("flower.png");
    CGImageRef dstImage;
    //dstImage = [self.calibrator drawCheccBoardCornersOnFrame:pixelBuffer];
    //cv::cvtColor(image, image, CV_RGBA2GRAY);
    cv::Size boardSize;
    boardSize.height = 7;
    boardSize.width = 7;
    
    _cameraCalibrator = new CameraCalibrator();
    //image = _cameraCalibrator->drawBoardCorners(image, boardSize);
    cv::cvtColor(image, image, CV_BGRA2GRAY);
    
    CGColorSpaceRef colorSpace;
    // (create color space, create graphics context, render buffer)
    CGBitmapInfo bitmapInfo ;  //= kcgb;
    
    // basically we decide if it's a grayscale, rgb or rgba image
    if (image.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
        bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
        bitmapInfo = kCGBitmapByteOrder32Little | (
                                                   image.elemSize() == 3? kCGImageAlphaNone : kCGImageAlphaNoneSkipFirst
                                                   );
    }
    
    
    
    NSData *data = [NSData dataWithBytes:image.data length:image.elemSize()*image.total()];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    dstImage = CGImageCreate(image.cols,                                 // width
                             image.rows,                                 // height
                             8,                                          // bits per component
                             8 * image.elemSize(),                       // bits per pixel
                             image.step,                                 // bytesPerRow
                             colorSpace,                                 // colorspace
                             bitmapInfo,                                 // bitmap info
                             provider,                                   // CGDataProviderRef
                             NULL,                                       // decode
                             false,                                      // should interpolate
                             kCGRenderingIntentDefault                   // intent
                             );
    
    CGDataProviderRelease(provider);
    
    CGColorSpaceRelease(colorSpace);
    
    
    //CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
    return (CVPixelBufferRef)CFRetain( pixelBuffer );
    //_imageView.image = [UIImage imageWithCGImage:dstImage];
    
    
}

-(VideoFrame)renderFrame:(VideoFrame )frame{

    cv::Mat image = [ImageManager cvMatFromVideoFrame:frame];
    cv::cvtColor(image, image, CV_BGRA2GRAY);
    NSLog(@"%d",image.channels());
    return frame;
}

- (void)renderMat:(cv::Mat &)cvMat{
    
    cv::cvtColor(cvMat, cvMat, CV_BGRA2RGBA);
    //_cameraCalibrator = new CameraCalibrator();
    //cv::Size boardSize;
    //boardSize.height = 7;
    //boardSize.width = 7;
    //cvMat = _cameraCalibrator->drawBoardCorners(cvMat, boardSize);
    //[calibrator drawCheccBoardCornersOnFrame:cvMat];
    NSLog(@"%d",cvMat.channels());
    //return frame;
}

@end

