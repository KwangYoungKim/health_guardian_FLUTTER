import UIKit
import Flutter
import Photos
import AudioToolbox

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var alarmTimer: Timer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.example.health_guardian_flutter/ringtone_picker",
                                      binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      if call.method == "saveImageToGallery" {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "FilePath is missing", details: nil))
          return
        }
        self.saveImage(path: filePath, result: result)
      } else if call.method == "startRingtone" {
        let args = call.arguments as? [String: Any]
        let vibrate = args?["vibrate"] as? Bool ?? true
        let uri = args?["uri"] as? String ?? "default"
        self.startAlarmSound(uri: uri, vibrate: vibrate)
        result(nil)
      } else if call.method == "stopRingtone" {
        self.stopAlarmSound()
        result(nil)
      } else if call.method == "vibrate" {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        result(nil)
      } else if call.method == "getDefaultAlarmUri" {
        result("default")
      } else if call.method == "getTimeZoneName" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startAlarmSound(uri: String, vibrate: Bool) {
    stopAlarmSound()
    alarmTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
      if uri != "silent" && uri != "무음" {
        AudioServicesPlayAlertSound(1005)
      }
      if vibrate || uri == "vibrate" || uri == "진동" {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      }
    }
    alarmTimer?.fire()
  }

  private func stopAlarmSound() {
    alarmTimer?.invalidate()
    alarmTimer = nil
  }

  private func saveImage(path: String, result: @escaping FlutterResult) {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: path) {
      if let image = UIImage(contentsOfFile: path) {
        PHPhotoLibrary.requestAuthorization { status in
          var isAllowed = (status == .authorized)
          if #available(iOS 14.0, *) {
            if status == .limited {
              isAllowed = true
            }
          }
          if isAllowed {
            PHPhotoLibrary.shared().performChanges({
              PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
              DispatchQueue.main.async {
                if success {
                  result(true)
                } else {
                  result(FlutterError(code: "SAVE_FAILED", message: error?.localizedDescription, details: nil))
                }
              }
            }
          } else {
            DispatchQueue.main.async {
              result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library access denied", details: nil))
            }
          }
        }
      } else {
        result(FlutterError(code: "LOAD_FAILED", message: "Failed to load image from file", details: nil))
      }
    } else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "File does not exist", details: nil))
    }
  }
}
