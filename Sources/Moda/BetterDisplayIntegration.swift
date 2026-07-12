import Foundation

enum BetterDisplayIntegration {
  private static let requestName = Notification.Name(
    "pro.betterdisplay.BetterDisplay.request"
  )

  private struct Request: Encodable {
    let uuid: String
    let commands: [String]
    let parameters: [String: String?]
  }

  static func setBrightness(_ level: Float32) -> Bool {
    let request = Request(
      uuid: UUID().uuidString,
      commands: ["set"],
      parameters: [
        "brightness": String(VolumeMath.clamped(level)),
        "displayWithMouse": nil,
      ]
    )
    guard
      let data = try? JSONEncoder().encode(request),
      let payload = String(data: data, encoding: .utf8)
    else { return false }

    DistributedNotificationCenter.default().postNotificationName(
      requestName,
      object: payload,
      userInfo: nil,
      deliverImmediately: true
    )
    return true
  }
}

@MainActor
final class BetterDisplayObserver {
  typealias Handler = (HUDSnapshot) -> Void

  private static let osdName = Notification.Name(
    "pro.betterdisplay.BetterDisplay.osd"
  )

  private let handler: Handler
  private var token: NSObjectProtocol?

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func start() {
    guard token == nil else { return }
    token = DistributedNotificationCenter.default().addObserver(
      forName: Self.osdName,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let payload = notification.object as? String else { return }
      Task { @MainActor in self?.handle(payload: payload) }
    }
  }

  func stop() {
    if let token {
      DistributedNotificationCenter.default().removeObserver(token)
    }
    token = nil
  }

  private func handle(payload: String) {
    guard let snapshot = BetterDisplayOSDParser.snapshot(from: payload) else { return }
    handler(snapshot)
  }
}

enum BetterDisplayOSDParser {
  private struct NotificationPayload: Decodable {
    let displayID: Int?
    let systemIconID: Int?
    let controlTarget: String?
    let value: Double?
    let maxValue: Double?
  }

  static func snapshot(from payload: String) -> HUDSnapshot? {
    guard
      let data = payload.data(using: .utf8),
      let notification = try? JSONDecoder().decode(NotificationPayload.self, from: data),
      notification.systemIconID == 1 || notification.controlTarget?.contains("Brightness") == true,
      let value = notification.value
    else { return nil }

    let maximum = max(notification.maxValue ?? 1, 0.000_001)
    return HUDSnapshot(
      control: .displayBrightness,
      level: VolumeMath.clamped(Float32(value / maximum)),
      targetDisplayID: notification.displayID.flatMap(UInt32.init(exactly:))
    )
  }
}
