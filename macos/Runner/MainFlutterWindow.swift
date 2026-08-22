import Cocoa
import CryptoKit
import FlutterMacOS
import IOKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerDesktopDeviceIdentity(with: flutterViewController)

    super.awakeFromNib()
  }

  private func registerDesktopDeviceIdentity(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.tivuq.iptv/device_identity",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getIdentity" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let uuid = Self.platformUuid() else {
        result(
          FlutterError(
            code: "identity_unavailable",
            message: "Mac cihaz kimliği okunamadı.",
            details: nil
          )
        )
        return
      }
      let binding = Self.sha256(uuid)
      let code = "MAC-" + String(binding.prefix(12)).uppercased()
      result([
        "deviceCode": code,
        "publicKey": "desktop-owner-build",
        "model": Host.current().localizedName ?? "Mac",
        "deviceBinding": binding,
        "signingCertificateSha256": ""
      ])
    }
  }

  private static func platformUuid() -> String? {
    let service = IOServiceGetMatchingService(
      kIOMasterPortDefault,
      IOServiceMatching("IOPlatformExpertDevice")
    )
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(
      service,
      kIOPlatformUUIDKey as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? String
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
