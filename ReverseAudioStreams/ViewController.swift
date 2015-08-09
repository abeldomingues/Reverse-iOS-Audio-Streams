//
//  ViewController.swift
//  ReverseAudioStreams
//
//  Created by Abel Domingues on 8/2/15.
//  Copyright (c) 2015 Abel Domingues. All rights reserved.
//

import UIKit
import MediaPlayer
import AVFoundation

class ViewController: UIViewController, MPMediaPickerControllerDelegate, FileReaderDelegate, OutputDataSource {
  
  // UI Controls
  @IBOutlet var playPauseButton : UIButton!
  @IBOutlet var songTitleLabel : UILabel!
  @IBOutlet var artistLabel : UILabel!
  @IBOutlet var scrubSlider : UISlider!
  @IBOutlet var reversePlaybackSwitch : UISegmentedControl!

  // Player
  var reader : FileReader!
  var output : Output!
  var isPlaying : Bool!

  override func viewDidLoad()
  {
    super.viewDidLoad()

    output = Output()
    output.outputDataSource = self
    
    // Initialize our user interface
    playPauseButton.enabled = false
    isPlaying = false
    scrubSlider.enabled = false
    scrubSlider.value = 0.0;
    reversePlaybackSwitch.selectedSegmentIndex = 1
    reversePlaybackSwitch.enabled = false
  }
  
  func createPlayerWithAssetFile(assetURL: NSURL)
  {
    // check if we have an existing reader, zap it if we do
    if (reader != nil) {
      reader = nil
    }
    reader = FileReader(fileURL: assetURL)
    reader.delegate = self

    playPauseButton.enabled = true
    scrubSlider.value = 0.0
    scrubSlider.enabled = true
    reversePlaybackSwitch.enabled = true
  }
  
  func startOutputUnit()
  {
    output.startOutputUnit()
  }
  
  func stopOutputUnit()
  {
    output.stopOutputUnit()
  }
  
  // MARK: Actions
  @IBAction func browseIpodLibrary(sender: UIButton)
  {
    var picker = MPMediaPickerController(mediaTypes: .Music)
    picker.showsCloudItems = false
    picker.prompt = "Choose a File"
    picker.allowsPickingMultipleItems = false
    picker.delegate = self
    
    presentViewController(picker, animated: true, completion: nil)
  }
  
  @IBAction func playPause(sender: UIButton)
  {
    if isPlaying == false {
      startOutputUnit()
      sender.setTitle("Pause", forState: .Normal)
      isPlaying = true
    } else {
      stopOutputUnit()
      sender.setTitle("Play", forState: .Normal)
      isPlaying = false
    }
  }
  
  @IBAction func reversePlayback(sender: UISegmentedControl)
  {
    if reader != nil {
      if sender.selectedSegmentIndex == 0 {
        reader.reversePlayback = true
      } else {
        reader.reversePlayback = false
      }
    }
  }
  
  @IBAction func seekToFrame(sender: UISlider)
  {
    var frameToSeekTo = Double(reader.totalFramesInFile) * Double(sender.value)
    reader.seekToFrame(Int64(frameToSeekTo))
  }
  
  @IBAction func didSeekToFrame(sender: UISlider)
  {
    var frameToSeekTo = Double(reader.totalFramesInFile) * Double(sender.value)
    reader.seekToFrame(Int64(frameToSeekTo))
  }
  
  // MARK: File Reader Delegate
  func audioFile(audioFile: FileReader!, updatedPosition: Int64) {
    dispatch_async(dispatch_get_main_queue(), {
      if( !self.scrubSlider.touchInside ){
        let newPosition = Float(updatedPosition) / Float(self.reader.totalFramesInFile)
        self.scrubSlider.value = newPosition
      }
    });
  }
  
  // MARK: Output Data Source
  func readFrames(frames: UInt32, audioBufferList: UnsafeMutablePointer<AudioBufferList>, bufferSize: UnsafeMutablePointer<UInt32>) {
    if reader != nil {
      reader.readFrames(frames, audioBufferList: audioBufferList, bufferSize: bufferSize)
    }
  }
  
  // MARK: Media Picker Delegate
  func mediaPicker(mediaPicker: MPMediaPickerController!, didPickMediaItems mediaItemCollection: MPMediaItemCollection!) 
  {
    dismissViewControllerAnimated(true, completion: nil)
    if mediaItemCollection.count < 1 {
      print("Sorry, the returned mediaItemCollection appeart to be empty")
      return
    }
    let mediaItem = mediaItemCollection.items[0] as! MPMediaItem
    let assetURL = mediaItem.valueForProperty(MPMediaItemPropertyAssetURL) as! NSURL
    
    // Check to make sure we've actually got something...
    if assetURL.isEqual(nil) {
      createNilFileAlert()
    }
    // ... and that we haven't picked an iCloud item not present on the device
    if mediaItem.valueForProperty(MPMediaItemPropertyIsCloudItem).isEqual(true) {
      createCloudItemAlert()
    }
    
    // Otherwise, we're good to go
    createPlayerWithAssetFile(assetURL)
    
    // Display the loaded track's title
    songTitleLabel.text = mediaItem.valueForProperty(MPMediaItemPropertyTitle) as? String
    artistLabel.text = mediaItem.valueForProperty(MPMediaItemPropertyArtist) as? String
  }
  
  func mediaPickerDidCancel(mediaPicker: MPMediaPickerController!) {
    dismissViewControllerAnimated(true, completion: nil)
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }
  
  // Mark - Helpers
  func createNilFileAlert()
  {
    var nilFileAlert = UIAlertController(title: "File Not Available", message: "The selected track failed to load from the iPod Library; please select another track", preferredStyle: .Alert)
    var OKAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
    
    nilFileAlert.addAction(OKAction)
    presentViewController(nilFileAlert, animated: true, completion: nil)
  }
  
  func createCloudItemAlert()
  {
    var iCloudItemAlert = UIAlertController(title: "File Not Available", message: "Sorry, the selected file appears to be an iCloud item and is not presently available on this device", preferredStyle: .Alert)
    var OKAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
    
    iCloudItemAlert.addAction(OKAction)
    presentViewController(iCloudItemAlert, animated: true, completion: nil)
  }
  
}

