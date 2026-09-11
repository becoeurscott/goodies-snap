import SwiftUI
import AVFoundation

/// A looping, aspect-filling video player for an uploaded reel clip. Plays only while the
/// reel is the active page (`isActive`), which keeps off-screen reels silent and idle, and
/// honours a shared mute toggle. Built on AVPlayerLayer so it fills the screen like TikTok.
/// It preloads as soon as it mounts (adjacent reels buffer ahead) and calls `onReady` when the
/// first frame is ready to show, so the feed can hold a poster over the black loading frame.
struct ReelVideoPlayer: UIViewRepresentable {
    let url: URL
    var isActive: Bool
    var isMuted: Bool
    var onReady: () -> Void = {}

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.onReady = onReady
        view.load(url: url)
        return view
    }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        view.onReady = onReady
        view.load(url: url)                 // no-op if the url is unchanged
        view.setMuted(isMuted)
        view.setActive(isActive)
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: ()) {
        view.teardown()
    }

    final class LoopingPlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?
        private var active = false
        private var readyObservation: NSKeyValueObservation?
        private var didSignalReady = false
        var onReady: () -> Void = {}

        func load(url: URL) {
            guard url != currentURL else { return }
            currentURL = url
            teardown()

            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            queue.actionAtItemEnd = .advance
            looper = AVPlayerLooper(player: queue, templateItem: item)
            queue.isMuted = true
            playerLayer.player = queue
            playerLayer.videoGravity = .resizeAspectFill
            player = queue

            // Fire onReady once the layer actually has a frame to display — the moment the
            // poster can be lifted without exposing a black frame.
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak self] layer, _ in
                guard let self, layer.isReadyForDisplay, !self.didSignalReady else { return }
                self.didSignalReady = true
                DispatchQueue.main.async { self.onReady() }
            }

            if active { queue.play() }
        }

        func setMuted(_ muted: Bool) { player?.isMuted = muted }

        func setActive(_ isActive: Bool) {
            guard active != isActive else { return }
            active = isActive
            if isActive {
                player?.seek(to: .zero)
                player?.play()
            } else {
                player?.pause()
            }
        }

        func teardown() {
            readyObservation?.invalidate()
            readyObservation = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            playerLayer.player = nil
            player = nil
        }
    }
}
