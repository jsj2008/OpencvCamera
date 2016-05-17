//
//  ViewController.h
//  RenderCamera
//
//  Created by Anastasia Tarasova on 12/04/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#import "VideoPreviewView.h"
#import "VideoProcessor.h"

@interface ARViewController : UIViewController <VideoProcessorDelegate> {
    VideoProcessor *videoProcessor;
    VideoPreviewView *previewView;
    UIBackgroundTaskIdentifier backgroundRecordingID;
    dispatch_queue_t progressQueue;
}
@property (strong, nonatomic) IBOutlet UIButton *recordButton;

- (IBAction)toggleRecording:(id)sender;

@end

