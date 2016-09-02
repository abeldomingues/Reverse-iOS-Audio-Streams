//
//  FileReader.m
//  MOJOFileReader
//
//  Created by Abel Domingues on 5/15/15.
//  Copyright (c) 2015 Abel Domingues. All rights reserved.
//

#import "FileReader.h"
#import "Utilities.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreGraphics/CoreGraphics.h>

#define kExpandedBufferSize 4096

@interface FileReader() {
  float **_floatBuffers;
  AudioBufferList* fileReadingBufferList;
  uint64_t timeOfLastSeek;
}

@property (assign, nonatomic) ExtAudioFileRef audioFile;
@property (assign, nonatomic) SInt64 frameIndex;
@property (assign, nonatomic) BOOL isMP3;

@end

@implementation FileReader

- (FileReader *)initWithFileURL:(NSURL*)url
{
  NSLog(@"FileReader - initWithFileURL");
  self = [super init];
  if (!self) {
    NSLog(@"Init Failed");
    return nil;
  }
  
  _isReading = NO;
  _reversePlayback = NO;
  _isMP3 = NO;
  // get our file
  [self openFileAtURL:url];
  
  return self;
}

- (void)openFileAtURL:(NSURL*)url
{
  // Open the selected audio file
  self.audioFile = NULL;
  CFURLRef cfurl = (__bridge CFURLRef)url;
  OSStatus error = ExtAudioFileOpenURL(cfurl, &_audioFile);
  if (error != 0) {
    NSLog(@"ExtAudioFileOpenURL Failed");
  }

  // Get the total number of frames in the file
  [self getTotalNumberFramesInFile];
  
  // Get the file's format
  [self getFileDataFormat];
  
  // Check if we're dealing with an MP3 file
  self.isMP3 = [self fileIsMP3:_fileFormat.mFormatID] ? YES : NO;
  
  // Set the client and waveform formats
  [self setClientFormatForAudioFile];
  
  // Set loop markers for our file start and end points
  [self setFileRegionMarkers];
  
  // Create the AudioBuffers for file reading
  [self createFileReadingBufferList];
  
  // Reset the frame index
  self.frameIndex = 0;
}

-(void)readFrames:(UInt32)frames
  audioBufferList:(AudioBufferList *)audioBufferList
       bufferSize:(UInt32 *)bufferSize
{
  if (self.audioFile) {
    self.isReading = YES;
    
    // Get our current location in the file
    SInt64 currentFrame;
    CheckError(ExtAudioFileTell(_audioFile, &currentFrame), nil);
       
// File Reading
    UInt32 framesToRead;
    if (self.isMP3 && self.reversePlayback) {
      // Larger reads for reversed MP3s
      framesToRead = kExpandedBufferSize;
      // Check our current location against the file's loop markers
      [self checkCurrentFrameAgainstLoopMarkers:currentFrame inFrames:framesToRead];
      // Seek and read
      CheckError(ExtAudioFileSeek(_audioFile, _frameIndex - (framesToRead - frames)), "MP3 ExtAudioFileSeek FAILED");
      CheckError(ExtAudioFileRead(_audioFile, &framesToRead, fileReadingBufferList),
                 "Failed to read audio data from audio file");
      // Crop our expanded (now filled) sample buffer
      for (int buff = 0; buff < fileReadingBufferList->mNumberBuffers; buff++) {
        Float32* croppedBuffer = fileReadingBufferList->mBuffers[buff].mData;
        croppedBuffer = &croppedBuffer[kExpandedBufferSize - frames];
        audioBufferList->mBuffers[buff].mData = croppedBuffer;
      }
    } else {
      // Normal reads otherwise
      framesToRead = frames;
      [self checkCurrentFrameAgainstLoopMarkers:currentFrame inFrames:framesToRead];
      CheckError(ExtAudioFileSeek(_audioFile, _frameIndex), "Non-MP3 ExtAudioFileSeek FAILED");
      CheckError(ExtAudioFileRead(_audioFile, &framesToRead, audioBufferList),
                 "Failed to read audio data from audio file");
    }
    
    // Reverse Playback
    if (self.reversePlayback) {
      for (int buff = 0; buff < audioBufferList->mNumberBuffers; buff++) {
        Float32* revBuff = audioBufferList->mBuffers[buff].mData;
        [self reverseContentsOfBuffer:revBuff numberOfFrames:frames];
      }
      _frameIndex -= frames; // decrement frame index
      if (_frameIndex < 0) { // check for out of bounds
        _frameIndex = 0;
      }
    } else {
      _frameIndex += frames; // increment frame index
      // TODO: I belive here should be check also for out of bounds, to avoid error kExtAudioFileError_InvalidSeek
    }
    
    // we're done reading
    self.isReading = NO;
    
    // Notify the delegate that our position in the file has been updated
    if( self.delegate ){
      if( [self.delegate respondsToSelector:@selector(audioFile:updatedPosition:)] ){
        [self.delegate audioFile:self updatedPosition:_frameIndex];
      }
    }
  }
}

- (void)setFileRegionMarkers
{
    self.startOfFile = 0;
    self.endOfFile = self.totalFramesInFile;
}

- (void)checkCurrentFrameAgainstLoopMarkers:(SInt64)currentFrame inFrames:(UInt32)frames
{
  if (self.reversePlayback) {
    // Check for left file marker: if we have fewer than a buffer's samples to go, reduce the read size
    if (currentFrame - (SInt64)frames < self.startOfFile) {
      frames = (UInt32)currentFrame;
    }
    // If we're *exactly* at startOfFile, seek directly to (endOfFile - frames)
    if (currentFrame - (SInt64)frames == self.startOfFile) {
      [self seekToFrame:self.endOfFile - frames];
    }
  } else { // forward
    // Check for right file marker: if we're there, seek to startOfFile
    if (currentFrame >= self.endOfFile) {
      [self seekToFrame:self.startOfFile];
    }
  }
}

- (Float32*)reverseContentsOfBuffer:(Float32*)audioBuffer numberOfFrames:(UInt32)frames
{
  Float32* reversedBuffer = audioBuffer;
  Float32 tmp;
  int i = 0;
  int j = frames - 1;

  
  while (j > i) {
    tmp = reversedBuffer[j];
    reversedBuffer[j] = reversedBuffer[i];
    reversedBuffer[i] = tmp;
    j--;
    i++;
  }
  
  return reversedBuffer;
}

-(void)seekToFrame:(SInt64)frame
{
  // Here, we're filtering the number of seek operations that can take place in a given window of time. The way we do it is by recording the time of our seek requests, and comparing each new request to the last one; if the incoming seek request occurs within the threshold of our window (here, 1/10th of second), we simply ignore it
  NSDate *currentTime = [NSDate date];
  NSTimeInterval timeInterval = [currentTime timeIntervalSinceDate:self.lastSeekTime];
  if (timeInterval < 0.1) {
    return;
  } else {
    // Otherwise, we perform the seek as usual...
    if (frame < self.startOfFile) {
      frame = 0;
    }
    CheckError(ExtAudioFileSeek(_audioFile,frame),
               "Failed to seek frame position within audio file");
  }
  _frameIndex = frame;
  // ... and record the time of the current seek for next time
  self.lastSeekTime = [NSDate date];
}

- (void)didSeekToFrame:(SInt64)frame
{
  // Notifies the delegate that the playhead has updated its position in the file, so that any appropriate UI elements can be kept sync with the frame index
  if( self.delegate ){
    if( [self.delegate respondsToSelector:@selector(audioFile:updatedPosition:)] ){
      [self.delegate audioFile:self updatedPosition:_frameIndex];
      NSLog(@"updated position for slider: %lld", _frameIndex);
    }
  }
}

- (void)getTotalNumberFramesInFile
{
  SInt64 totalFrames;
  UInt32 dataSize = sizeof(totalFrames);
  OSStatus err = ExtAudioFileGetProperty(_audioFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFrames);
  if (err != 0) {
    NSLog(@"ExtAudioFileGetProperty FileLengthFrames failed");
  }
  _totalFramesInFile = totalFrames;
}

- (void)getFileDataFormat
{
  UInt32 dataSize = sizeof(_fileFormat);
  CheckError(ExtAudioFileGetProperty(_audioFile, kExtAudioFileProperty_FileDataFormat, &dataSize, &_fileFormat), "ExtAudioFileGetProperty FileDataFormat failed");
}

- (void)setClientFormatForAudioFile
{
  // Stereo Non-Interleaved for the audio file
  UInt32 floatByteSize   = sizeof(float);
  _clientFormat.mChannelsPerFrame = 2;
  _clientFormat.mBitsPerChannel   = 8 * floatByteSize;
  _clientFormat.mBytesPerFrame    = floatByteSize;
  _clientFormat.mFramesPerPacket  = 1;
  _clientFormat.mBytesPerPacket   = _clientFormat.mFramesPerPacket * _clientFormat.mBytesPerFrame;
  _clientFormat.mFormatFlags      = kAudioFormatFlagIsFloat|kAudioFormatFlagIsNonInterleaved;
  _clientFormat.mFormatID         = kAudioFormatLinearPCM;
  _clientFormat.mSampleRate       = 44100;

  // Set the format
  CheckError(ExtAudioFileSetProperty(_audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(_clientFormat), &_clientFormat), "ExtAudioFileSetProperty Client Data Format FAILED");
}

- (void)createFileReadingBufferList
{
  // AudioBufferList, by default, contains a single buffer - any additional buffers need to be allocated by us
  fileReadingBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList) + (sizeof(AudioBuffer) * (_clientFormat.mChannelsPerFrame)));
  fileReadingBufferList->mNumberBuffers = _clientFormat.mChannelsPerFrame;
  
  for ( int i=0; i < fileReadingBufferList->mNumberBuffers; i++ ) {
    fileReadingBufferList->mBuffers[i].mNumberChannels = 1;
    UInt32 bufferSize;
    if (self.isMP3 == YES) {
      bufferSize = kExpandedBufferSize; // for reversed MP3 files
    } else {
      bufferSize = 1024;
    }
    fileReadingBufferList->mBuffers[i].mDataByteSize = bufferSize * sizeof(float);
    fileReadingBufferList->mBuffers[i].mData = malloc(bufferSize * sizeof(float));
  }
}

#pragma mark - Helpers

- (BOOL)fileIsMP3:(UInt32)formatID
{
  char formatIDString[5];
  UInt32 ID = CFSwapInt32HostToBig (formatID);
  bcopy (&ID, formatIDString, 4);
  formatIDString[4] = '\0';
  NSString* fileExtension = [NSString stringWithCString:formatIDString encoding:NSUTF8StringEncoding];

  if ([fileExtension isEqual: @".mp3"]) {
    return YES;
  }

  return NO;
}

- (AudioBufferList *)audioBufferListWithNumberOfFrames:(UInt32)frames
                                      numberOfChannels:(UInt32)channels
                                           interleaved:(BOOL)interleaved
{
  AudioBufferList *audioBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList));
  UInt32 outputBufferSize = 32 * frames; // 32 KB
  audioBufferList->mNumberBuffers = interleaved ? 1 : channels;
  for( int i = 0; i < audioBufferList->mNumberBuffers; i++ )
  {
    audioBufferList->mBuffers[i].mNumberChannels = channels;
    audioBufferList->mBuffers[i].mDataByteSize = channels * outputBufferSize;
    audioBufferList->mBuffers[i].mData = (float*)malloc(channels * sizeof(float) * outputBufferSize);
  }
  return audioBufferList;
}


@end
