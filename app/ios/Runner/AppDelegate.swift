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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MarthaAppIcon") else { return }
    // Alternate app icons for supporters. The icons are bundled asset
    // catalogs (AppIcon-Green, …), named in
    // ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES.
    let channel = FlutterMethodChannel(name: "martha/app_icon", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "current":
        let name = UIApplication.shared.alternateIconName
        result(name.map { String($0.dropFirst("AppIcon-".count)) })
      case "set":
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: nil, details: nil))
          return
        }
        let name = (call.arguments as? String).map { "AppIcon-\($0)" }
        UIApplication.shared.setAlternateIconName(name) { error in
          if let error = error {
            result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
