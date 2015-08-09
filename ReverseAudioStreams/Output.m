//
//  Output.m
//  iPodLibraryAccessDemo
//
//  Created by Abel Domingues on 5/15/15.
//  Copyright (c) 2015 Abel Domingues. All rights reserved.
//

#import "Output.h"
#import "Utilities.h"

static OSStatus OutputRenderCallback (void *inRefCon,
                                      AudioUnitRenderActionFlags	* ioActionFlags,
                                      const AudioTimeStamp * inTimeStamp,
                                      UInt32 inOutputBusNumber,
                                      UInt32 inNumberFrames,
                                      AudioBufferList * ioData)
{
  Output *self = (__bridge Output*)inRefCon;
  
  if (self.outputDataSource)
  {
    if ([self.outputDataSource respondsToSelector:@selector(readFrames:audioBufferList:bufferSize:)])
    {
      @autoreleasepool
      {
        UInt32 bufferSize;
        [self.outputDataSource readFrames:inNumberFrames audioBufferList:ioData bufferSize:&bufferSize];
      }
    }
  }
  
  return noErr;
}

@interface Output()
@property (nonatomic) AudioUnit audioUnit;
@end

@implementation Output

- (id)init
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  [self createAudioUnit];
  return self;
}

#pragma mark - Audio Unit Setup
- (void)createAudioUnit
{
  // create a component description
  AudioComponentDescription desc;
  desc.componentType = kAudioUnitType_Output;
  desc.componentSubType = kAudioUnitSubType_RemoteIO;
  desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  desc.componentFlags = 0;
  desc.componentFlagsMask = 0;
  // use the description to find the component we're looking for
  AudioComponent defaultOutput = AudioComponentFindNext(NULL, &desc);
  // create an instance of the component and have our _audioUnit property point to it
  CheckError(AudioComponentInstanceNew(defaultOutput, &_audioUnit),
             "AudioComponentInstanceNew Failed");
  // describe the output audio format... here we're using LPCM 32 bit, non-interleaved floating point samples
  AudioStreamBasicDescription outputFormat;
  UInt32 floatByteSize   = sizeof(float);
  outputFormat.mChannelsPerFrame = 2;
  outputFormat.mBitsPerChannel   = 8 * floatByteSize;
  outputFormat.mBytesPerFrame    = floatByteSize;
  outputFormat.mFramesPerPacket  = 1;
  outputFormat.mBytesPerPacket   = outputFormat.mFramesPerPacket * outputFormat.mBytesPerFrame;
  outputFormat.mFormatFlags      = kAudioFormatFlagIsFloat|kAudioFormatFlagIsNonInterleaved;
  outputFormat.mFormatID         = kAudioFormatLinearPCM;
  outputFormat.mSampleRate       = 44100;
  // set the audio format on the input scope (kAudioUnitScope_Input) of the output bus (0) of the output unit - got that?
  CheckError(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputFormat, sizeof(outputFormat)),
             "AudioUnitSetProperty StreamFormat Failed");
  // set up a render callback struct consisting of our output render callback (above) and a reference to self (so we can access our outputDataSource reference from within the callback)
  AURenderCallbackStruct callbackStruct;
  callbackStruct.inputProc = OutputRenderCallback;
  callbackStruct.inputProcRefCon = (__bridge void*)self;
  // add the callback struct to the output unit (again, that's to the input scope of the output bus)
  CheckError(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct)),
             "AudioUnitSetProperty SetRenderCallback Failed");
  // initialize the unit
  CheckError(AudioUnitInitialize(_audioUnit),
             "AudioUnitInitializeFailed");
}

#pragma mark - Start/Stop
- (void)startOutputUnit
{
  CheckError(AudioOutputUnitStart(_audioUnit), "Audio Output Unit Failed To Start");
}

- (void)stopOutputUnit
{
  CheckError(AudioOutputUnitStop(_audioUnit), "Audio Output Unit Failed To Stop");
}

@end
