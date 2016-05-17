//
//  CVImageUtil.m
//  OpenCV AR
//
//  Created by Anastasia Tarasova on 15/02/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//



#import "ImageManager.h"
//#import <opencv2/opencv.hpp>
//#import "opencv2/imgcodecs/ios.h"

@interface ImageManager()
@property (nonatomic)CVImageBufferRef imageBuffer;
@property (nonatomic)CGColorSpaceRef csrColorSpace;
@property (nonatomic)uint8_t *baseAddress;
@property (nonatomic)size_t sztBytesPerRow;
@property (nonatomic)size_t sztWidth;
@property (nonatomic)size_t sztHeight;
@property (nonatomic)CGContextRef cnrContext;
@property (nonatomic)CGImageRef imrImage;
@end

@implementation ImageManager


+(VideoFrame)videoFrameFromPixelBuffer:(CVPixelBufferRef)pixelBuffer{

    

    
    // Since the OpenCV Mat is wrapping the CVPixelBuffer's pixel data, we must do all of our modifications while its base address is locked.
    // If we want to operate on the buffer later, we'll have to do an expensive deep copy of the pixel data, using memcpy or Mat::clone().
    
    // Use extendedWidth instead of width to account for possible row extensions (sometimes used for memory alignment).
    // We only need to work on columms from [0, width - 1] regardless.
    
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow( pixelBuffer );
    
    
    struct VideoFrame frame;
    
    frame.width = width;
    frame.height = height;
    frame.bytesPerRow = bytesPerRow;
    frame.baseAddress = base;
    
    return frame;
}

+(cv::Mat)cvMatFromVideoFrame:(VideoFrame)frame{

    // cv::Mat bgraFrame = cv::Mat( (int)frame.height, (int)frame.bytesPerRow/ sizeof( uint32_t ), CV_8UC4, frame.baseAddress );
     //cv::Mat bgraFrame(frame.height, frame.width, CV_8UC4, frame.baseAddress, frame.bytesPerRow);
    cv::Mat bgraFrame(frame.height,frame.width, CV_8UC4, frame.baseAddress, frame.bytesPerRow);
    return bgraFrame;
}

+ (cv::Mat ) createMatFromImageBuffer:(CVPixelBufferRef) pixelBuffer{
    
    /*Lock image buffer*/
   // CVPixelBufferLockBaseAddress(imageBuffer,0);
    
    
   /* void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    int bytesPerRow = (int)CVPixelBufferGetBytesPerRow(imageBuffer);
    int height = (int)CVPixelBufferGetHeight(imageBuffer);
    int width = (int)CVPixelBufferGetWidth(imageBuffer);
    
    // Extract the frame, convert it to grayscale, and shove it in _frame.
    cv::Mat bgraFrame(height, width, CV_8UC4, baseAddress, bytesPerRow);*/
    
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t stride = CVPixelBufferGetBytesPerRow( pixelBuffer );
    size_t extendedWidth = stride / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits
    
    cv::Mat bgraFrame = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    
    return bgraFrame;

}

+(CGImageRef)cgImageFromMat:(cv::Mat)cvMat{

    
    CGImageRef dstImage;
    
    CGColorSpaceRef colorSpace;
    CGBitmapInfo bitmapInfo ;
    
    // basically we decide if it's a grayscale, rgb or rgba image
    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
        bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
        bitmapInfo = kCGBitmapByteOrder32Little | (
                                                   cvMat.elemSize() == 3? kCGImageAlphaNone : kCGImageAlphaNoneSkipFirst
                                                   );
    }
    
    NSData *data = [NSData dataWithBytes:cvMat.data
                                  length:cvMat.elemSize()*cvMat.total()];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    dstImage = CGImageCreate(cvMat.cols,                                 // width
                             cvMat.rows,                                 // height
                             8,                                          // bits per component
                             8 * cvMat.elemSize(),                       // bits per pixel
                             cvMat.step,                                 // bytesPerRow
                             colorSpace,                                 // colorspace
                             bitmapInfo,                                 // bitmap info
                             provider,                                   // CGDataProviderRef
                             NULL,                                       // decode
                             false,                                      // should interpolate
                             kCGRenderingIntentDefault                   // intent
                             );
    
    CGDataProviderRelease(provider);
    
    CGColorSpaceRelease(colorSpace);

    return dstImage;
}

+(CVPixelBufferRef) pixelBufferFromCGImage:(CGImageRef) image{
    CVPixelBufferRef pxbuffer = NULL;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    
    size_t width =  CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    size_t bytesPerRow = CGImageGetBytesPerRow(image);
    
    
    CFDataRef  dataFromImageDataProvider = CGDataProviderCopyData(CGImageGetDataProvider(image));
    GLubyte  *imageData = (GLubyte *)CFDataGetBytePtr(dataFromImageDataProvider);
    
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                 width,
                                 height,
                                 kCVPixelFormatType_32BGRA,
                                 imageData,bytesPerRow,
                                 NULL,
                                 NULL,
                                 (__bridge CFDictionaryRef)options,
                                 &pxbuffer);
    
    CFRelease(dataFromImageDataProvider);
    
    return pxbuffer;
}

/*+ (CMSampleBufferRef)sampleBufferFromCGImage:(CGImageRef)image
{
    CVPixelBufferRef pixelBuffer = [self pixelBufferFromCGImage:image];
    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleTimingInfo timimgInfo = kCMTimingInfoInvalid;
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(
                                                 NULL, pixelBuffer, &videoInfo);
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       pixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       videoInfo,
                                       &timimgInfo,
                                       &newSampleBuffer);
    
    return newSampleBuffer;
}

+ (CMSampleBufferRef)sampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer// withTime:(CMTime)time withDescription:(CMFormatDescriptionRef)description
{
    
    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleTimingInfo timimgInfo = kCMTimingInfoInvalid;
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(
                                                 NULL, pixelBuffer, &videoInfo);
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       pixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       videoInfo,
                                       &timimgInfo,
                                       &newSampleBuffer);
    
    return newSampleBuffer;
}*/

@end