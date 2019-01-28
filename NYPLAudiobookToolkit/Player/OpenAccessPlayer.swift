import AVFoundation

final class OpenAccessPlayer: NSObject, Player {
    
    var playbackRate: PlaybackRate = .normalTime
    
    var isLoaded = true
    
    func movePlayheadToLocation(_ location: ChapterLocation) {
        
    }
    
    func chapterIsPlaying(_ location: ChapterLocation) -> Bool {
        return false
    }
    
    var currentChapterLocation: ChapterLocation? {
        return ChapterLocation(
            number: self.chapterAtCursor.number,
            part: self.chapterAtCursor.part,
            duration: self.chapterAtCursor.duration,
            startOffset: 0,
            playheadOffset: self.queuePlayer.currentTime().seconds,     //godo todo wip
            title: self.chapterAtCursor.title,
            audiobookID: self.audiobookID
        )
    }

    func registerDelegate(_ delegate: PlayerDelegate) {
        self.delegates.add(delegate)
    }
    
    func removeDelegate(_ delegate: PlayerDelegate) {
        self.delegates.remove(delegate)
    }
    
    func seekTo(_ offsetInChapter: Float) {
    }

    func playAtLocation(_ chapter: ChapterLocation) {

    }
    
    func skipPlayhead(_ timeInterval: TimeInterval, completion: ((ChapterLocation)->())? = nil) -> () {
        
    }
    
    var isPlaying: Bool {
        return false
    }

    func play() {

        if self.readyForPlayback {
            self.queuePlayer.play()
        } else {
            ATLog(.error, "User attempted to play before the player was ready.")
            //godo todo consider doing some kind of queueing here similar to how findawayplayer handles it
        }
    }
    
    func pause() {
        
    }
  
    func unload() {
        self.isLoaded = false
    }



    private var chapterAtCursor: ChapterLocation {
        return self.cursor.currentElement.chapter
    }

    private let audiobookID: String
    private var cursor: Cursor<SpineElement>
    private let queuePlayer: AVQueuePlayer
    private var readyForPlayback: Bool = false
    private var openAccessPlayerContext = 0

    var delegates: NSHashTable<PlayerDelegate> = NSHashTable(options: [NSPointerFunctions.Options.weakMemory])

    //godo todo all a work in progress
    required init(cursor: Cursor<SpineElement>, audiobookID: String) {

        self.cursor = cursor
        self.audiobookID = audiobookID

        var items = [AVPlayerItem]()

        var cursor: Cursor<SpineElement>? = self.cursor
        let currentElement = cursor?.currentElement
        var assetURL = (currentElement?.downloadTask as? OpenAccessDownloadTask)?.localDirectory()

        // Queue up items to the AVQueuePlayer
        while (assetURL != nil) {
            let playerItem = AVPlayerItem(url: assetURL!)
            items.append(playerItem)

            cursor = cursor?.next()
            let nextElement = cursor?.currentElement
            assetURL = (nextElement?.downloadTask as? OpenAccessDownloadTask)?.localDirectory()
        }

        self.queuePlayer = AVQueuePlayer(items: items)

        super.init()

        self.queuePlayer.addObserver(self,
                                     forKeyPath: #keyPath(AVQueuePlayer.status),
                                     options: [.old, .new],
                                     context: &openAccessPlayerContext)

        self.queuePlayer.addObserver(self,
                                     forKeyPath: #keyPath(AVQueuePlayer.rate),
                                     options: [.old, .new],
                                     context: &openAccessPlayerContext)

    }
}

/// Key-Value Observing on AVPlayer properties
extension OpenAccessPlayer {
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {

        guard context == &openAccessPlayerContext else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
            return
        }

        if keyPath == #keyPath(AVQueuePlayer.status) {
            let status: AVQueuePlayer.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVQueuePlayer.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }

            switch status {
            case .readyToPlay:
                ATLog(.debug, "AVQueuePlayer status: ready to play.")
                self.readyForPlayback = true
            case .failed:
                let error = (object as? AVQueuePlayer)?.error.debugDescription ?? "error: nil"
                ATLog(.error, "AVQueuePlayer status: failed to get ready for playback. Error:\n\(error)")
            case .unknown:
                ATLog(.debug, "AVQueuePlayer status: unknown.")
            }
        }
        else if keyPath == #keyPath(AVQueuePlayer.rate) {
            // godo todo wip
            if let newRate = change?[.newKey] as? Float,
                let oldRate = change?[.oldKey] as? Float,
                let player = (object as? AVQueuePlayer),
                let location = self.currentChapterLocation {
                if (oldRate == 0.0) && (newRate != 0.0) && (player.error == nil) {
                    notifyDelegatesOfPlaybackFor(chapter: location)
                }
            }
        }
    }

    fileprivate func notifyDelegatesOfPlaybackFor(chapter: ChapterLocation) {
        self.delegates.allObjects.forEach { (delegate) in
            delegate.player(self, didBeginPlaybackOf: chapter)
        }
    }

    fileprivate func notifyDelegatesOfPauseFor(chapter: ChapterLocation) {
        self.delegates.allObjects.forEach { (delegate) in
            delegate.player(self, didStopPlaybackOf: chapter)
        }
    }

    fileprivate func notifyDelegatesOfPlaybackFailureFor(chapter: ChapterLocation, _ error: NSError?) {
        self.delegates.allObjects.forEach { (delegate) in
            delegate.player(self, didFailPlaybackOf: chapter, withError: error)
        }
    }

    fileprivate func notifyDelegatesOfPlaybackEndFor(chapter: ChapterLocation) {
        self.delegates.allObjects.forEach { (delegate) in
            delegate.player(self, didComplete: chapter)
        }
    }

    fileprivate func notifyDelegatesOfUnloadRequest() {
        self.delegates.allObjects.forEach { (delegate) in
            delegate.playerDidUnload(self)
        }
    }
}
