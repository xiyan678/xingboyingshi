#if os(iOS)
import AVKit
import Flutter
import UIKit

// Reuses the video_player AVPlayer. No second item, download, seek or audio stream.
final class XingboSharedPip: NSObject, AVPictureInPictureControllerDelegate {
  private let channel: FlutterMethodChannel
  private let lookup: (Int64) -> AVPlayer?
  private var controller: AVPictureInPictureController?
  private var host: UIView?
  private var layer: AVPlayerLayer?
  private var observation: NSKeyValueObservation?
  private var timeout: DispatchWorkItem?
  private var pending: FlutterResult?
  private var playerId: Int64?
  private var restoring = false
  private var requested = false

  init(messenger: FlutterBinaryMessenger, lookup: @escaping (Int64) -> AVPlayer?) {
    channel = FlutterMethodChannel(name: "xingbo/shared_pip", binaryMessenger: messenger)
    self.lookup = lookup
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any],
              let id = args["playerId"] as? NSNumber else {
          result(FlutterError(code: "INVALID_PLAYER", message: "Missing player ID", details: nil))
          return
        }
        self.start(id: id.int64Value, result: result)
      case "close":
        self.cleanup()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func start(id: Int64, result: @escaping FlutterResult) {
    guard pending == nil, !(controller?.isPictureInPictureActive ?? false) else {
      result(FlutterError(code: "PIP_BUSY", message: "PiP already starting or active", details: nil))
      return
    }
    cleanup()
    guard AVPictureInPictureController.isPictureInPictureSupported(),
          let player = lookup(id), player.currentItem?.status == .readyToPlay,
          let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
      result(FlutterError(code: "PIP_UNAVAILABLE", message: "Player or window not ready", details: nil))
      return
    }
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    host.isUserInteractionEnabled = false
    host.clipsToBounds = true
    let layer = AVPlayerLayer(player: player)
    layer.frame = host.bounds
    host.layer.addSublayer(layer)
    window.insertSubview(host, at: 0)
    guard let pip = AVPictureInPictureController(playerLayer: layer) else {
      host.removeFromSuperview()
      result(FlutterError(code: "PIP_UNAVAILABLE", message: "Cannot create PiP", details: nil))
      return
    }
    self.host = host
    self.layer = layer
    controller = pip
    playerId = id
    pending = result
    pip.delegate = self
    if #available(iOS 14.2, *) {
      pip.canStartPictureInPictureAutomaticallyFromInline = false
    }
    observation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
      [weak self] observed, _ in
      DispatchQueue.main.async {
        guard let self = self, self.controller === observed,
              observed.isPictureInPicturePossible, !self.requested,
              self.pending != nil else { return }
        self.requested = true
        observed.startPictureInPicture()
      }
    }
    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self, self.pending != nil else { return }
      self.finish(FlutterError(code: "PIP_TIMEOUT", message: "PiP did not become ready", details: nil))
      self.cleanup()
    }
    self.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
  }

  private func finish(_ error: FlutterError? = nil) {
    timeout?.cancel()
    timeout = nil
    let callback = pending
    pending = nil
    callback?(error)
  }

  func detach(playerId: Int64) {
    if self.playerId == playerId { cleanup() }
  }

  private func cleanup() {
    finish(FlutterError(code: "PIP_CANCELLED", message: "Playback session closed", details: nil))
    observation?.invalidate()
    observation = nil
    controller?.delegate = nil
    controller?.stopPictureInPicture()
    controller = nil
    // Detach the extra layer without pausing or disposing the shared player.
    layer?.player = nil
    layer?.removeFromSuperlayer()
    layer = nil
    host?.removeFromSuperview()
    host = nil
    playerId = nil
    restoring = false
    requested = false
  }

  func dispose() {
    cleanup()
    channel.setMethodCallHandler(nil)
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pip: AVPictureInPictureController) {
    guard controller === pip else { return }
    finish()
  }

  func pictureInPictureController(_ pip: AVPictureInPictureController,
      failedToStartPictureInPictureWithError error: Error) {
    guard controller === pip else { return }
    finish(FlutterError(code: "PIP_FAILED", message: error.localizedDescription, details: nil))
    cleanup()
  }

  func pictureInPictureController(_ pip: AVPictureInPictureController,
      restoreUserInterfaceBeforeStoppingWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    restoring = true
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pip: AVPictureInPictureController) {
    guard controller === pip else { return }
    let restore = restoring
    let id = playerId
    if !restore, let id = id { lookup(id)?.pause() }
    cleanup()
    channel.invokeMethod("stopped", arguments: ["restore": restore, "playerId": id ?? -1])
  }
}
#endif
