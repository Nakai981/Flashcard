import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let widgetChannelName = "com.chibi.flashcard/widget"
  private let appGroupId = "group.com.chibi.flashcard"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ChibiDailyWidgetPlugin") {
      let channel = FlutterMethodChannel(
        name: widgetChannelName,
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        if call.method == "updateWidget" {
          if let args = call.arguments as? [String: Any] {
            let word = args["word"] as? String ?? "Serendipity"
            let phonetic = args["phonetic"] as? String ?? ""
            let meaning = args["meaning"] as? String ?? ""
            let summary = args["summary"] as? String ?? "💎 Từ mới Chibi trong ngày"

            // 1. Lưu vào App Group UserDefaults (nếu có)
            if let groupDefaults = UserDefaults(suiteName: self.appGroupId) {
              groupDefaults.set(word, forKey: "chibi_widget_word")
              groupDefaults.set(phonetic, forKey: "chibi_widget_phonetic")
              groupDefaults.set(meaning, forKey: "chibi_widget_meaning")
              groupDefaults.set(summary, forKey: "chibi_widget_summary")
              groupDefaults.synchronize()
            }

            // 2. Lưu file JSON vào App Group Container (nếu có)
            if let containerUrl = FileManager.default.containerURL(
              forSecurityApplicationGroupIdentifier: self.appGroupId
            ) {
              let fileUrl = containerUrl.appendingPathComponent("chibi_daily_widget.json")
              let payload: [String: String] = [
                "word": word,
                "phonetic": phonetic,
                "meaning": meaning,
                "summary": summary
              ]
              if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? data.write(to: fileUrl, options: .atomic)
              }
            }
          }

          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
