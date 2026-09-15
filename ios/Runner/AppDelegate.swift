import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "XingboLinks")!
    let channel = FlutterMethodChannel(name: "xingbo/links", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let value = call.arguments as? String,
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            ["https", "http"].contains(scheme),
            let host = url.host, !host.isEmpty else {
        result(FlutterError(code: "invalid_url", message: "无效的广告链接", details: nil))
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { opened in
          if opened {
            result(nil)
          } else {
            result(FlutterError(code: "open_failed", message: "无法打开链接", details: nil))
          }
        }
      }
    }
  }
}
