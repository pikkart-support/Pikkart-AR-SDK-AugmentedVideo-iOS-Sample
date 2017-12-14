//
//  PikkartVideoPlayer.swift
//  testPKTRecognitionFrameworkApp
//
//  Created by Roberto Avanzi on 16/08/16.
//  Copyright © 2016 Pikkart. All rights reserved.
//

import UIKit

open class PikkartVideoPlayer: NSObject {

    fileprivate class VideoOutputShared:AVPlayerItemVideoOutput {
        
        static fileprivate var innerSharedInstance:VideoOutputShared!
        
        static func sharedInstance() -> VideoOutputShared {
            if (innerSharedInstance == nil) {
                let settings:[String:AnyObject] = [String(kCVPixelBufferPixelFormatTypeKey):
                                                   Int(kCVPixelFormatType_32BGRA) as AnyObject]
                innerSharedInstance = VideoOutputShared(pixelBufferAttributes:settings)
                innerSharedInstance.suppressesPlayerRendering = true;
            }
            return innerSharedInstance
        }
    }
    
    public enum VIDEO_STATE:Int {
        case reached_END = 0
        case paused
        case stopped
        case playing
        case ready
        case not_READY
        case error
    }
    
    // Constants
    static let  PLAYER_CURSOR_POSITION_MEDIA_START:Float = 0.0
    static let  PLAYER_CURSOR_REQUEST_COMPLETE:Float = -1.0
    static let  PLAYER_VOLUME_DEFAULT:Float = 1.0
    static let  TIMESCALE:Float = 1000;  // 1 millisecond granularity for time
    static let  VIDEO_PLAYBACK_CURRENT_POSITION:Float = 1.0

    // The number of bytes per texel (when using kCVPixelFormatType_32BGRA)
    static let BYTES_PER_TEXEL:Int = 4;
    
    static let StatusKey:String = "status"
    static let TracksKey:String = "tracks"
    static let RateKey:String = "rate"
    static var AVPlayerItemStatusObservationContext:UnsafeMutableRawPointer? = nil
    static var AVPlayerRateObservationContext:UnsafeMutableRawPointer? = nil

    fileprivate var mediaState:VIDEO_STATE = .not_READY
    open  var videoStatus:VIDEO_STATE { return mediaState }
    
    fileprivate var requestedCursorPosition:Float = PLAYER_CURSOR_REQUEST_COMPLETE
    fileprivate var playerCursorPosition:Float = PLAYER_CURSOR_POSITION_MEDIA_START
    fileprivate var playImmediately:Bool = false
    open  var videoSize:CGSize = CGSize.zero
    open  var videoLengthSeconds:Float64 = 0
    fileprivate var videoFrameRate:Float = 0
    fileprivate var player:AVPlayer?
    open  var videoTextureHandle:GLuint = 0
    
    fileprivate var mediaURL:URL?
    fileprivate var assetReader:AVAssetReader?
    fileprivate var assetReaderTrackOutputVideo:AVAssetReaderTrackOutput?
    fileprivate var asset:AVURLAsset?
    fileprivate var latestSampleBuffer:CMSampleBuffer?
    fileprivate var currentSampleBuffer:CMSampleBuffer?
    fileprivate var dataLock:NSLock = NSLock()
    fileprivate var videoOutput:AVPlayerItemVideoOutput?
    fileprivate var playerCursorStartPosition:CMTime = CMTime();
    fileprivate var currentVolume:Float = 0;

    // used for video creation
    fileprivate var lastMissingBufferFrameTime:TimeInterval = -1
    fileprivate var nbrMissingBufferFrame:UInt = 0
    
    
    fileprivate func resetData() {
        
         mediaState = .not_READY
         requestedCursorPosition = PikkartVideoPlayer.PLAYER_CURSOR_REQUEST_COMPLETE
         playerCursorPosition = PikkartVideoPlayer.PLAYER_CURSOR_POSITION_MEDIA_START
         playImmediately = false
         videoSize.width = 0.0
         videoSize.height = 0.0
         videoLengthSeconds = 0.0
         videoFrameRate = 0.0
         
         // Remove KVO observers
        if (player != nil) {
            player!.currentItem!.removeObserver(self, forKeyPath: PikkartVideoPlayer.StatusKey)
            player!.removeObserver(self, forKeyPath: PikkartVideoPlayer.RateKey)
        
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object:player!.currentItem!)
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemPlaybackStalled, object:player!.currentItem!)
        }
        
        
        // Release AVPlayer, AVAsset, etc.
        player = nil;
        asset = nil;
        assetReader = nil;
        assetReaderTrackOutputVideo = nil;
        mediaURL = nil;
        
        // Video sample buffer lock
        latestSampleBuffer = nil;
        currentSampleBuffer = nil;
        lastMissingBufferFrameTime = -1;
        nbrMissingBufferFrame = 0;
        
        // Class data lock
        dataLock = NSLock();

    }
    
    //MARK: init method
    override init() {
        
        super.init()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback,
                                                            with: .mixWithOthers)
        } catch let error {
            print("Error during audio configuration \(error)")
        }
        
        resetData()
    }
    
    fileprivate func prepareAssetForReading(_ startTime:CMTime) -> Bool {
        
        let arrayTracks = asset!.tracks(withMediaType: AVMediaType.audio)
        
        guard arrayTracks.count == 0 else {
            let assetTrackAudio = arrayTracks[0]
            let audioInputParams = AVMutableAudioMixInputParameters()
            audioInputParams.setVolume(0.1, at: playerCursorStartPosition)
            audioInputParams.trackID = assetTrackAudio.trackID
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [audioInputParams]
            player!.currentItem!.audioMix = audioMix
            return true
        }
        
        return false
    }
    
    fileprivate func prepareAVPlayer() {
        
        if let realAsset = asset {
            // Create a player item
            let item = AVPlayerItem(asset: realAsset)
            // Add player item status KVO observer
            let opts = NSKeyValueObservingOptions.new;
            item.addObserver(self, forKeyPath: PikkartVideoPlayer.StatusKey, options:opts,
                             context:&PikkartVideoPlayer.AVPlayerItemStatusObservationContext)
            // Create an AV player
            player = AVPlayer(playerItem: item)
            player!.volume = 1.0
            item.add(videoOutput!)
            // Add player rate KVO observer
            player!.addObserver(self, forKeyPath: PikkartVideoPlayer.RateKey, options: opts,
                                context:&PikkartVideoPlayer.AVPlayerRateObservationContext)
            NotificationCenter.default.addObserver(self, selector:#selector(self.itemDidFinishPlaying(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object:item)
             NotificationCenter.default.addObserver(self, selector:#selector(self.itemStalledPlaying(_:)), name: NSNotification.Name.AVPlayerItemPlaybackStalled, object:item)
        }
    }
    
    fileprivate func prepareAssetForPlayback() -> Bool {
        // Get video properties
        let videoTracks = asset!.tracks(withMediaType: AVMediaType.video)
        let videoTrack = videoTracks[0];
        videoSize = videoTrack.naturalSize;
        
        videoLengthSeconds = CMTimeGetSeconds(asset!.duration);
        
        // Start playback at time 0.0
        playerCursorStartPosition = kCMTimeZero;
        
        // Start playback at full volume (audio mix level, not system volume level)
        currentVolume = PikkartVideoPlayer.PLAYER_VOLUME_DEFAULT;
        
        // Prepare the AVPlayer to play the audio
        prepareAVPlayer()
        
        // Create asset tracks for reading
        let ret = prepareAssetForReading(playerCursorStartPosition)
        
        if (ret) {
            // Inform our client that the asset is ready to play
            mediaState = .ready;
        }
        
        return ret;
    }
    
    fileprivate func loadLocalMedia(_ url:URL) -> Bool {
        var ret = false
        
        asset =  AVURLAsset(url: url)
        
        if ( asset != nil) {
            ret = true
            asset!.loadValuesAsynchronously(forKeys: [PikkartVideoPlayer.TracksKey], completionHandler: {
                OperationQueue.main.addOperation({
                    var error:NSError?
                    let status:AVKeyValueStatus = self.asset!.statusOfValue(forKey: PikkartVideoPlayer.TracksKey, error: &error)
                    if (status == .loaded) {
                        // Asset loaded, retrieve info and prepare
                        // for playback
                        self.videoOutput = VideoOutputShared.sharedInstance()
                        if (self.prepareAssetForPlayback() == false) {
                            print("Error - Unable to prepare media for playback")
                            self.mediaState = .error
                        }
                    }
                })
            })
        }
        return ret;
    }
    
    @objc fileprivate func itemDidFinishPlaying(_ notification:Notification) {
        mediaState = .reached_END
        
        let startTime = CMTime(value: CMTimeValue(PikkartVideoPlayer.PLAYER_CURSOR_POSITION_MEDIA_START * PikkartVideoPlayer.TIMESCALE), timescale: CMTimeScale(PikkartVideoPlayer.TIMESCALE))
        player!.seek(to: startTime)
    }
    
    @objc fileprivate func playAfterStalled(_ sender:AnyObject) {
        if (mediaState == .playing) {
            player?.play()
        }
    }
    
    @objc fileprivate func itemStalledPlaying(_ notification:Notification) {
        OperationQueue.main.addOperation({
            self.perform(#selector(self.playAfterStalled(_:)), with: nil, afterDelay: 1.0)
        })
    }

    fileprivate func updatePlayerCursorPosition(_ position:Float) {
        self.playerCursorPosition = position
        self.requestedCursorPosition = position
    }

    //MARK:public methods
    open func load(_ filename:String, playImmediately:Bool, seekPosition:Float) -> Bool {
        var ret = false
        
        guard mediaState != .not_READY &&
              mediaState != .error else {
            let defaultManager = FileManager.default
            if defaultManager.fileExists(atPath: filename) {
                mediaURL = URL(fileURLWithPath: filename)
            } else {
                mediaURL = URL(string: filename);
            }
            
            mediaState = .ready
            self.playImmediately = playImmediately
            if (0.0 <= seekPosition) {
              self.updatePlayerCursorPosition(seekPosition)
            }
            ret = self.loadLocalMedia(mediaURL!)
            if (ret == false) {
                mediaState = .error
            }
            return ret
        }
        
        print("Media already loaded. Unload current media first")
        return ret
    }
    
    open func play(_ seekposition:Float) -> Bool {
        var ret = false
        
        if (mediaState != .playing &&
            mediaState != .error) {
            
            if (seekposition > 0.0) {
                self.updatePlayerCursorPosition(seekposition)
            }
            dataLock.lock()
            mediaState = .playing
            player!.play()
            dataLock.unlock()
            ret = true
        }
        return ret
    }
    
    open func pause() -> Bool {
        var ret = false
        if (mediaState == .playing) {
            dataLock.lock()
            mediaState = .paused
            player!.pause()
            dataLock.unlock()
            ret = true;
        }
        return ret
    }
    
    open func stop() -> Bool {
        var ret = false
        if (mediaState == .playing) {
            dataLock.lock()
            mediaState = .stopped
            player!.pause()
            self.updatePlayerCursorPosition(PikkartVideoPlayer.PLAYER_CURSOR_POSITION_MEDIA_START)
            dataLock.unlock()
            ret = true;
        }
        return ret
    }
    
    open func seekTo(_ position:Float) -> Bool {
        var ret = false;
        if (mediaState != .error &&
            Float64(position) < self.videoLengthSeconds) {
            self.updatePlayerCursorPosition(position)
            ret = true
        }
        return ret
    }
    
    open func updateVideoData() {
        if (mediaState == .playing) {
            var pixelBufferBaseAddress:UnsafeMutablePointer<UInt8>
            var pixelBuffer:CVPixelBuffer?
            
            let desiredTime = player!.currentItem!.currentTime
            let lastDesiredTime = TimeInterval(desiredTime().value)/TimeInterval(desiredTime().timescale)
            
            pixelBuffer = videoOutput!.copyPixelBuffer(forItemTime: desiredTime(), itemTimeForDisplay: nil)
            
            if (pixelBuffer == nil) {return}
            
            if (videoTextureHandle == 0) {return}
            
            CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            let baseAddress=CVPixelBufferGetBaseAddress(pixelBuffer!)
            pixelBufferBaseAddress=(baseAddress?.assumingMemoryBound(to: UInt8.self))!
            
            glBindTexture(GLenum(GL_TEXTURE_2D), videoTextureHandle)
            
            let bytesPerRow:size_t = CVPixelBufferGetBytesPerRow(pixelBuffer!)
            
            if (CGFloat(bytesPerRow / PikkartVideoPlayer.BYTES_PER_TEXEL) == videoSize.width) {
                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(videoSize.width), GLsizei(videoSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), pixelBufferBaseAddress);
            } else {
                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(videoSize.width), GLsizei(videoSize.height), 0, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil);
                
                // Now upload each line of texture data as a sub-image
                for i in 0..<Int(videoSize.height) {
                    let line:UnsafeMutablePointer<UInt8> = pixelBufferBaseAddress + i * bytesPerRow;
                    glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, GLint(i), GLsizei(videoSize.width), 1, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), line);
                }
            }
            
            //print("reproduce video at time = \(lastDesiredTime) with VideoSize \(videoSize)\n")
            
            glBindTexture(GLenum(GL_TEXTURE_2D), 0);
            
            // Unlock the buffers
            CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)));
            
        }
    }
    
    //MARK: AVPlayer observation methods
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if (context == PikkartVideoPlayer.AVPlayerItemStatusObservationContext) {
            let val:Int = change![NSKeyValueChangeKey.newKey] as! Int
            let status:AVPlayerItemStatus = AVPlayerItemStatus(rawValue:val)!
            switch status {
                case .unknown:
                    print("AVPlayerItemStatusObservationContext -> AVPlayerItemStatusUnknown")
                    mediaState = .not_READY
                case .readyToPlay:
                    print("AVPlayerItemStatusObservationContext -> AVPlayerItemStatusReadyToPlay")
                    if (mediaState != .playing) {
                        mediaState = .ready
                        if (playImmediately == true) {
                            self.play(PikkartVideoPlayer.VIDEO_PLAYBACK_CURRENT_POSITION)
                        }
                    }
                case .failed:
                    print("AVPlayerItemStatusObservationContext -> AVPlayerItemStatusFailed\n")
                    mediaState = .error
                    let errorLog:AVPlayerItemErrorLog? = player!.currentItem!.errorLog()
                    if (errorLog != nil) {
                        let logString = String(describing:errorLog!.extendedLogData())
                        print("Error - AVPlayer unable to play media: \(logString)")
                    }
            }
        }
    }
    
    //MARK: deinitializer method
    deinit {
        self.stop()
        self.resetData()
    }
}
