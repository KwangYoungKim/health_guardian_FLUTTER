import UIKit
import Flutter
import Photos

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.example.health_guardian_flutter/ringtone_picker",
                                      binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "saveImageToGallery" {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "FilePath is missing", details: nil))
          return
        }
        self.saveImage(path: filePath, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
