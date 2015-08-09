//
//  Utilities.h
//  SwiftChopSuey
//
//  Created by Abel Domingues on 7/29/15.
//  Copyright (c) 2015 Abel Domingues. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AudioToolbox;

@interface Utilities : NSObject

extern void CheckError(OSStatus error, const char *operation);

+ (void)printErrorMessage: (NSString *) errorString withStatus: (OSStatus) result;

+ (void) printASBD: (AudioStreamBasicDescription) asbd;

+ (NSString*)descriptionForAudioFormat:(AudioStreamBasicDescription) audioFormat;

+ (NSString*)descriptionForStandardFlags:(UInt32) mFormatFlags;

@end
