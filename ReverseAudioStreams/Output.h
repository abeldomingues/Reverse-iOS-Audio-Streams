//
//  Output.h
//  iPodLibraryAccessDemo
//
//  Created by Abel Domingues on 5/15/15.
//  Copyright (c) 2015 Abel Domingues. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@class Output;

@protocol OutputDataSource <NSObject>

- (void)readFrames:(UInt32)frames
   audioBufferList:(AudioBufferList *)audioBufferList
        bufferSize:(UInt32 *)bufferSize;

@end

@interface Output : NSObject

@property (strong, nonatomic) id outputDataSource;

- (void)startOutputUnit;
- (void)stopOutputUnit;


@end
