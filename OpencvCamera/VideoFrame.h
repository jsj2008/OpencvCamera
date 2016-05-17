//
//  VideoFrame.h
//  AR Camera
//
//  Created by Anastasia Tarasova on 21/03/16.
//  Copyright © 2016 Anastasia Tarasova. All rights reserved.
//

#ifndef VideoFrame_h
#define VideoFrame_h


#include <stddef.h>

typedef struct VideoFrame
{
    size_t width;
    size_t height;
    size_t bytesPerRow;
    
    //unsigned char * baseAddress;
    void *baseAddress;
    
}VideoFrame;

#endif /* VideoFrame_h */