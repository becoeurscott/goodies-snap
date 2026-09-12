import SwiftUI
import WebKit

/// A YouTube reel that autoplays while it's the active page and pauses when scrolled away.
///
/// Unlike the recipe-detail player (a plain embed), this hosts the IFrame Player API in an
/// HTML shell so the app can call `playVideo`/`pauseVideo` as pages change — without reloading
/// the web view each time, which would stutter the feed. It also cues the video as soon as it
/// mounts (so neighbouring reels preload) and reports back the moment real playback starts, so
/// the feed can keep a poster frame over the YouTube chrome until there's a frame to show.
/// The video loops and fills the screen.
struct ReelYouTubePlayer: UIViewRepresentable {
    let videoID: String
    var isActive: Bool
    var isMuted: Bool
    /// Fired once, when the player reaches the PLAYING state — i.e. real video is on screen.
    var onReady: () -> Void = {}

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "reelReady")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isUserInteractionEnabled = false   // taps belong to the overlay, not YouTube
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html(videoID: videoID), baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
        guard context.coordinator.ready else {
            context.coordinator.pendingActive = isActive
            context.coordinator.pendingMuted = isMuted
            return
        }
        apply(webView, active: isActive, muted: isMuted)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "reelReady")
    }

    private func apply(_ webView: WKWebView, active: Bool, muted: Bool) {
        webView.evaluateJavaScript(muted ? "player.mute();" : "player.unMute();")
        webView.evaluateJavaScript(active ? "player.playVideo();" : "player.pauseVideo();")
    }

    func makeCoordinator() -> Coordinator { Coordinator(apply: apply, onReady: onReady) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var ready = false
        var pendingActive = false
        var pendingMuted = true
        var onReady: () -> Void
        private let apply: (WKWebView, Bool, Bool) -> Void

        init(apply: @escaping (WKWebView, Bool, Bool) -> Void, onReady: @escaping () -> Void) {
            self.apply = apply
            self.onReady = onReady
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The player needs a moment after the API script loads before it accepts commands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.ready = true
                self.apply(webView, self.pendingActive, self.pendingMuted)
            }
        }

        /// The HTML posts here on every PLAYING transition. The cell re-covers the poster on
        /// each activation, so forwarding every PLAYING (not just the first) lets it lift the
        /// poster the moment playback actually resumes.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "reelReady" else { return }
            onReady()
        }
    }

    private static func html(videoID: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html,body{margin:0;height:100%;background:#000;overflow:hidden}
          /* Fit the native 16:9 frame within the screen (letterboxed) rather than cropping it
             to fill — keeps the whole YouTube video visible. */
          #player{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
                  width:100vw;height:56.25vw;max-height:100vh;max-width:177.78vh}
        </style></head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player;
          function onYouTubeIframeAPIReady(){
            player = new YT.Player('player', {
              videoId: '\(videoID)',
              playerVars: {playsinline:1, controls:0, rel:0, modestbranding:1, fs:0,
                           iv_load_policy:3, loop:1, playlist:'\(videoID)'},
              events: {
                'onReady': function(e){ e.target.mute(); },
                'onStateChange': function(e){
                  if(e.data===YT.PlayerState.PLAYING){
                    try { window.webkit.messageHandlers.reelReady.postMessage(1); } catch(err){}
                  }
                  if(e.data===YT.PlayerState.ENDED){ player.seekTo(0); player.playVideo(); }
                }
              }
            });
          }
        </script></body></html>
        """
    }
}
