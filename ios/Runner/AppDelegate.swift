import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
  GeneratedPluginRegistrant.register(with: self)
  // Firebase API Key
  let firebaseApiKey = "AIzaSyDCKnKno70u6E7o2i2JLivcReyx9MWPXLc"
  // You may need to configure Firebase here if using Firebase SDK
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
