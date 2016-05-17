//
//  ViewController.m
//  OpencvCamera
//
//  Created by Anastasia Tarasova on 16/05/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"

#import <QuartzCore/QuartzCore.h>
#import "CapturePipeline.h"
#import "OpenGLPixelBufferView.h"

#import "CalibrationWrapper.h"

@interface ViewController () <CapturePipelineDelegate, UIAlertViewDelegate>
{
    BOOL _addedObservers;
    BOOL _allowedToUseGPU;
    BOOL _mainCameraUIAdapted;
    
    BOOL _recording;
    UIBackgroundTaskIdentifier _backgroundRecordingID;
}
@property(strong,nonatomic)CalibrationWrapper* calibrator;

@property(nonatomic, strong) IBOutlet UIBarButtonItem *photoButton;
@property(nonatomic, strong) IBOutlet UIBarButtonItem *flashButton;
@property(nonatomic, strong) IBOutlet UIBarButtonItem *shareButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *recordButton;
@property(nonatomic, strong) IBOutlet UIToolbar *toolbar;
@property(nonatomic, strong) IBOutlet UILabel *framerateLabel;
@property(nonatomic, strong) IBOutlet UILabel *dimensionsLabel;
@property(nonatomic, strong) IBOutlet UIView *contentView;
@property(nonatomic, strong) IBOutlet UIView *noCameraPermissionOverlayView;
@property(nonatomic, strong) NSTimer *labelTimer;
@property(nonatomic, strong) OpenGLPixelBufferView *previewView;
@property(nonatomic, strong) CapturePipeline *capturePipeline;

@property(nonatomic, strong) AVCaptureDevice *videoDevice;

@end

@implementation ViewController

@synthesize calibrator;

- (void)dealloc
{
    if ( _addedObservers ) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:[UIApplication sharedApplication]];
        [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    }
}

#pragma mark - View lifecycle

- (void)applicationDidEnterBackground
{
    // Avoid using the GPU in the background
    _allowedToUseGPU = NO;
    self.capturePipeline.renderingEnabled = NO;
    
    [self.capturePipeline stopRecording];
    
    // We reset the OpenGLPixelBufferView to ensure all resources have been clear when going to the background.
    [self.previewView reset];
}

- (void)didReceiveMemoryWarning
{
    [self.previewView reset];
    [super didReceiveMemoryWarning];
}

- (void)applicationWillEnterForeground
{
    _allowedToUseGPU = YES;
    self.capturePipeline.renderingEnabled = YES;
}

- (void)viewDidLoad
{
    calibrator = [[CalibrationWrapper alloc]init];
    self.capturePipeline = [[CapturePipeline alloc] init];
    [self.capturePipeline setDelegate:self callbackQueue:dispatch_get_main_queue()];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:[UIApplication sharedApplication]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(adjustOrientation)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:[UIApplication sharedApplication]];
    
    // Keep track of changes to the device orientation so we can update the capture pipeline
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
    _addedObservers = YES;
    
    // the willEnterForeground and didEnterBackground notifications are subsequently used to update _allowedToUseGPU
    _allowedToUseGPU = ( [UIApplication sharedApplication].applicationState != UIApplicationStateBackground );
    self.capturePipeline.renderingEnabled = _allowedToUseGPU;
    
    [super viewDidLoad];
    
    [self checkCameraPrivacySettings];
    
    // Adapt UI for default device (will be called again when capture session starts)
    [self setVideoDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]];
}

- (void)setVideoDevice:(AVCaptureDevice *)videoDevice
{
    _videoDevice = videoDevice;
    
    if (_mainCameraUIAdapted == NO)
    {
#if TARGET_IPHONE_SIMULATOR
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
#endif
            if (!videoDevice.hasTorch)
            {
                // remove torch button if main camera does not have it
                NSMutableArray *items = self.toolbar.items.mutableCopy;
                [items removeObjectAtIndex:0];
                [items removeObjectAtIndex:0];
                self.toolbar.items = items;
            }
        _mainCameraUIAdapted = YES;
    }
    
    self.flashButton.enabled = videoDevice.torchAvailable;
#if TARGET_IPHONE_SIMULATOR
    self.flashButton.enabled = YES;
#endif
    [self reflectTorchActiveState:videoDevice.torchActive];
}

- (void)reflectTorchActiveState:(BOOL)torchActive
{
    NSString *torchImageName = torchActive ? @"FlashLight" : @"FlashDark";
    UIImage *torchImage = [UIImage imageNamed:torchImageName];
    self.flashButton.image = torchImage;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self.capturePipeline startRunning];
    
    self.labelTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateLabels) userInfo:nil repeats:YES];
    
#if TARGET_IPHONE_SIMULATOR
    // wait after autolayout did its work
    [self setupPreviewView];
    // display some test image
    //	[self.previewView displayImage:[UIImage imageWithContentsOfFile:@"test-image.jpg"]];
#endif
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self.labelTimer invalidate];
    self.labelTimer = nil;
    
    [self.capturePipeline stopRunning];
    [UIApplication sharedApplication].idleTimerDisabled = NO;//need it?
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}
/*
- (void)deviceOrientationDidChange
{
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    
    // Update recording orientation if device changes to portrait or landscape orientation (but not face up/down)
    if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
        [self.capturePipeline setRecordingOrientation:(AVCaptureVideoOrientation)deviceOrientation];
    }
}*/


#pragma mark - UI

- (IBAction)toggleRecording:(id)sender
{
    if ( _recording )
    {
        [self.capturePipeline stopRecording];
    }
    else
    {
        // Disable the idle timer while recording
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        
        // Make sure we have time to finish saving the movie if the app is backgrounded during recording
        if ( [[UIDevice currentDevice] isMultitaskingSupported] ) {
            _backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
        }
        
        self.recordButton.enabled = NO; // re-enabled once recording has finished starting
        self.recordButton.title = @"Stop";
        
        [self.capturePipeline startRecording];
        
        _recording = YES;
    }
}

- (void)recordingStopped
{
    _recording = NO;
    self.recordButton.enabled = YES;
    self.recordButton.title = @"Record";
    
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    [[UIApplication sharedApplication] endBackgroundTask:_backgroundRecordingID];
    _backgroundRecordingID = UIBackgroundTaskInvalid;
}


- (IBAction)toggleShowFramerate:(UIGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state)
    {
        case UIGestureRecognizerStateBegan:
            self.framerateLabel.hidden = !self.framerateLabel.hidden;
            self.dimensionsLabel.hidden = !self.dimensionsLabel.hidden;
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            //self.framerateLabel.hidden = YES;
            //self.dimensionsLabel.hidden = YES;
            break;
        case UIGestureRecognizerStateChanged:
        case UIGestureRecognizerStatePossible:
            break;
    }
}

- (IBAction)zoom:(UIPinchGestureRecognizer *)gestureRecognizer
{
    NSError *error;
    switch (gestureRecognizer.state)
    {
        case UIGestureRecognizerStateBegan:
            [_videoDevice lockForConfiguration:&error];
            gestureRecognizer.scale = _videoDevice.videoZoomFactor;
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [_videoDevice unlockForConfiguration];
            break;
        case UIGestureRecognizerStateChanged:
        {
            CGFloat factor = gestureRecognizer.scale;
            CGFloat minFactor = 1;
            CGFloat maxFactor = MIN(_videoDevice.activeFormat.videoZoomFactorUpscaleThreshold*2, _videoDevice.activeFormat.videoMaxZoomFactor);
            _videoDevice.videoZoomFactor = MIN(maxFactor, MAX(minFactor, factor));
            break;
        }
        case UIGestureRecognizerStatePossible:
            break;
    }
}

- (IBAction)toggleInputDevice:(id)sender
{
    BOOL changed = [self.capturePipeline toggleInputDevice];
    if (changed)
    {
        [self.previewView reset];
        self.previewView.alpha = 0;
        self.flashButton.enabled = NO;
        [self reflectTorchActiveState:NO];
        [UIView transitionFromView:self.contentView toView:self.contentView duration:0.5 options:UIViewAnimationOptionTransitionFlipFromRight|UIViewAnimationOptionAllowAnimatedContent|UIViewAnimationOptionShowHideTransitionViews completion:^(BOOL success){
            [UIView animateWithDuration:0.2 animations:^{
                self.previewView.alpha = 1;
            }];
        }];
    }
}

- (IBAction)toggleTorch:(id)sender
{
    NSError *error = nil;
    if ([_videoDevice lockForConfiguration:&error])
    {
        BOOL torchActive = !_videoDevice.torchActive;
        [_videoDevice setTorchMode:torchActive ? AVCaptureTorchModeOn : AVCaptureTorchModeOff];
        [_videoDevice unlockForConfiguration];
        [self reflectTorchActiveState:torchActive];
    }
    else
        NSLog(@"videoDevice lockForConfiguration returned error %@", error);
}

- (IBAction)showSettings:(id)sender {
    UIViewController *vc = [[UIStoryboard storyboardWithName:@"Options" bundle:nil] instantiateInitialViewController];
    vc.view.tintColor = self.view.tintColor;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)setupPreviewView
{
    // Set up GL view
    self.previewView = [[OpenGLPixelBufferView alloc] initWithFrame:CGRectZero];
    self.previewView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    
    [self adjustOrientation];
    
    [self.contentView insertSubview:self.previewView atIndex:0];
    CGRect bounds = CGRectZero;
    bounds.size = [self.contentView convertRect:self.contentView.bounds toView:self.previewView].size;
    self.previewView.bounds = bounds;
    self.previewView.center = CGPointMake(self.contentView.bounds.size.width/2.0, self.contentView.bounds.size.height/2.0);
}

- (void)checkCameraPrivacySettings
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.noCameraPermissionOverlayView.hidden = granted;
        });
    }];
}

- (void)updateLabels
{
    NSString *frameRateString = [NSString stringWithFormat:@"%d FPS", (int)roundf(self.capturePipeline.videoFrameRate)];
    self.framerateLabel.text = frameRateString;
    
    NSString *dimensionsString = [NSString stringWithFormat:@"%d x %d", self.capturePipeline.videoDimensions.width, self.capturePipeline.videoDimensions.height];
    self.dimensionsLabel.text = dimensionsString;
}

- (void)showError:(NSError *)error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:error.localizedDescription
                                                        message:error.localizedFailureReason
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}

- (IBAction)showCameraPrivacySettings:(id)sender
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
}

#pragma mark - CapturePipelineDelegate

- (void)capturePipeline:(CapturePipeline *)capturePipeline didStartRunningWithVideoDevice:(AVCaptureDevice *)videoDevice
{
    self.videoDevice = videoDevice;
    [self adjustOrientation];
}

- (void)adjustOrientation {
    UIInterfaceOrientation currentInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    self.previewView.transform = [self.capturePipeline transformFromVideoBufferOrientationToOrientation:(AVCaptureVideoOrientation)currentInterfaceOrientation withAutoMirroring:NO]; // Front camera preview should be mirrored
    self.previewView.mirrorTransform = self.videoDevice.position == AVCaptureDevicePositionFront;
    self.previewView.frame = self.previewView.superview.bounds;
}

- (void)capturePipeline:(CapturePipeline *)capturePipeline didStopRunningWithError:(NSError *)error
{
    self.videoDevice = nil;
    
    [self showError:error];
    
    self.photoButton.enabled = NO;
    self.recordButton.enabled = NO;
}

// Preview
- (void)capturePipeline:(CapturePipeline *)capturePipeline previewPixelBufferReadyForDisplay:(CVPixelBufferRef)previewPixelBuffer
{
    if ( ! _allowedToUseGPU ) {
        return;
    }
    
    if ( ! self.previewView ) {
        [self setupPreviewView];
    }
    
    self.noCameraPermissionOverlayView.hidden = YES;
    
    
    [self.previewView displayPixelBuffer:previewPixelBuffer];
    
    UIApplication *app = [UIApplication sharedApplication];
    BOOL shouldDisableIdleTimer = (self.presentedViewController == nil);
    if (app.idleTimerDisabled != shouldDisableIdleTimer)
        app.idleTimerDisabled = shouldDisableIdleTimer;
}

- (void)capturePipelineDidRunOutOfPreviewBuffers:(CapturePipeline *)capturePipeline
{
    if ( _allowedToUseGPU ) {
        [self.previewView flushPixelBufferCache];
    }
}

-(CVPixelBufferRef)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer{
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t stride = CVPixelBufferGetBytesPerRow( pixelBuffer );
    size_t extendedWidth = stride / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits
    
    // Since the OpenCV Mat is wrapping the CVPixelBuffer's pixel data, we must do all of our modifications while its base address is locked.
    // If we want to operate on the buffer later, we'll have to do an expensive deep copy of the pixel data, using memcpy or Mat::clone().
    
    // Use extendedWidth instead of width to account for possible row extensions (sometimes used for memory alignment).
    // We only need to work on columms from [0, width - 1] regardless.
    cv::Mat bgraImage((int)height, (int)width, CV_8UC4, base, stride);
    //cv::Mat bgraImage = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    //cv::Mat grayImage;
    
    cv::Mat image_copy;
    cvtColor(bgraImage, image_copy, CV_BGRA2RGBA);
    
    //cv::morphologyEx(image_copy,image_copy,cv::MORPH_CLOSE,getStructuringElement( cv::MORPH_ELLIPSE,cv::Size(7,7)));
    //cvtColor(image_copy, image_copy, CV_RGB2GRAY);
    // invert image
    bitwise_not(image_copy, image_copy);
    image_copy.copyTo(bgraImage);
    
    // NSLog(@"%d",bgraImage.channels());
    //[calibrator drawCheccBoardCornersOnFrame:bgraImage];
    //cv::cvtColor(bgraImage, grayImage, CV_BGRA2GRAY);
    /*cv::adaptiveThreshold(image_copy,   // Input image
                          image_copy ,// Result binary image
                          255,         //
                          cv::ADAPTIVE_THRESH_GAUSSIAN_C,
                          cv::THRESH_BINARY_INV,
                          11,
                          5
                          );
    image_copy.copyTo(bgraImage);*/
    //bgraImage = grayImage;
   // cv::cvtColor(bgraImage, bgraImage, CV_BGRA2RGBA);
    
    /*for ( uint32_t y = 0; y < height; y++ )
    {
        for ( uint32_t x = 0; x < width; x++ )
        {
            
            bgraImage.at<cv::Vec<uint8_t,4> >(y,x)[1] = 0;
            
        }
    }*/
//#endif //DETECT_RECT
    
    CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
    return (CVPixelBufferRef)CFRetain( pixelBuffer );
}

#pragma mark - Recording

// Recording
- (void)capturePipelineRecordingDidStart:(CapturePipeline *)capturePipeline
{
    self.recordButton.enabled = YES;
}

- (void)capturePipelineRecordingWillStop:(CapturePipeline *)capturePipeline
{
    // Disable record button until we are ready to start another recording
    self.recordButton.enabled = NO;
    self.recordButton.title = @"Record";
}

- (void)capturePipelineRecordingDidStop:(CapturePipeline *)capturePipeline
{
    [self recordingStopped];
}

- (void)capturePipeline:(CapturePipeline *)capturePipeline recordingDidFailWithError:(NSError *)error
{
    [self recordingStopped];
    [self showError:error];
}



@end
