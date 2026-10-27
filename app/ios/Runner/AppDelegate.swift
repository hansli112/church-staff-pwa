import Flutter
import UIKit
import UserNotifications

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MarthaSettings") {
      let settings = FlutterMethodChannel(name: "martha/settings", binaryMessenger: registrar.messenger())
      settings.setMethodCallHandler { call, result in
        switch call.method {
        case "notifications":
          // Notifications turned off: iOS does not ask again, so this app's
          // notification settings are the way back.
          let page: String
          if #available(iOS 16.0, *) {
            page = UIApplication.openNotificationSettingsURLString
          } else {
            page = UIApplication.openSettingsURLString
          }
          if let url = URL(string: page) { UIApplication.shared.open(url) }
          result(nil)
        case "badge":
          // What is unread in the 通知列表 (#89), on the app icon.
          let count = call.arguments as? Int ?? 0
          if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count)
          } else {
            UIApplication.shared.applicationIconBadgeNumber = count
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MarthaAppIcon") else { return }
    // Alternate app icons, for supporters and churches with their own. The
    // icons are bundled asset catalogs (AppIcon-Green, …), named in
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
