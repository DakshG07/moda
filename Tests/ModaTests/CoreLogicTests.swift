import CoreGraphics
import XCTest

@testable import Moda

final class MediaKeyDecoderTests: XCTestCase {
  func testDecodesVolumeUpKeyDown() {
    let event = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 0, state: 0xA),
      modifierFlags: []
    )
    XCTAssertEqual(
      event,
      DecodedMediaKeyEvent(
        key: .volume(.up),
        phase: .down,
        isFineAdjustment: false,
        isCommandPressed: false
      )
    )
    XCTAssertEqual(
      MediaKeyDecoder.action(for: event!),
      .volume(.increase(step: 1.0 / 16.0))
    )
  }

  func testDecodesFineVolumeDownRepeat() {
    let event = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 1, state: 0xA) | 1,
      modifierFlags: [.maskAlternate, .maskShift]
    )
    XCTAssertEqual(
      event,
      DecodedMediaKeyEvent(
        key: .volume(.down),
        phase: .down,
        isFineAdjustment: true,
        isCommandPressed: false,
        isRepeat: true
      )
    )
    XCTAssertEqual(
      MediaKeyDecoder.action(for: event!),
      .volume(.decrease(step: 1.0 / 64.0))
    )
  }

  func testBrightnessAndCommandKeyboardBrightnessRouting() {
    let display = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 2, state: 0xA),
      modifierFlags: []
    )!
    XCTAssertEqual(display.key, .brightnessUp)
    XCTAssertEqual(MediaKeyRouting.control(for: display), .displayBrightness)
    XCTAssertEqual(
      MediaKeyDecoder.action(for: display),
      .brightness(target: .display, action: .increase(step: 1.0 / 16.0))
    )
    XCTAssertTrue(MediaKeyRouting.shouldDeferToDisplayHandler(display))

    let keyboard = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 3, state: 0xA),
      modifierFlags: [.maskCommand]
    )!
    XCTAssertTrue(keyboard.isCommandPressed)
    XCTAssertEqual(MediaKeyRouting.control(for: keyboard), .keyboardBrightness)
    XCTAssertFalse(MediaKeyRouting.shouldDeferToDisplayHandler(keyboard))
    XCTAssertEqual(
      MediaKeyDecoder.action(for: keyboard),
      .brightness(target: .keyboard, action: .decrease(step: 1.0 / 16.0))
    )
  }

  func testKeyUpIsConsumedButDoesNotMutate() {
    let event = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 7, state: 0xB),
      modifierFlags: []
    )
    XCTAssertEqual(event?.phase, .up)
    XCTAssertNil(MediaKeyDecoder.action(for: event!))
    XCTAssertTrue(MediaKeyRouting.shouldConsume(event, deviceCanHandle: true))
  }

  func testKeysPullImmediatelyOnlyAtTheRequestedBoundary() {
    let volumeUpRepeat = DecodedMediaKeyEvent(
      key: .volume(.up),
      phase: .down,
      isFineAdjustment: false,
      isCommandPressed: false,
      isRepeat: true
    )
    XCTAssertEqual(
      HUDEdgeFeedback.pull(
        for: volumeUpRepeat,
        startingLevel: 1,
        resultingLevel: 1
      ),
      .upper
    )
    XCTAssertNil(
      HUDEdgeFeedback.pull(
        for: volumeUpRepeat,
        startingLevel: 0.94,
        resultingLevel: 1
      )
    )

    let brightnessDownRepeat = DecodedMediaKeyEvent(
      key: .brightnessDown,
      phase: .down,
      isFineAdjustment: false,
      isCommandPressed: true,
      isRepeat: true
    )
    XCTAssertEqual(
      HUDEdgeFeedback.pull(
        for: brightnessDownRepeat,
        startingLevel: 0,
        resultingLevel: 0
      ),
      .lower
    )

    var initialPress = volumeUpRepeat
    initialPress.isRepeat = false
    XCTAssertEqual(
      HUDEdgeFeedback.pull(
        for: initialPress,
        startingLevel: 1,
        resultingLevel: 1
      ),
      .upper
    )

    let keyUp = DecodedMediaKeyEvent(
      key: .volume(.up),
      phase: .up,
      isFineAdjustment: false,
      isCommandPressed: false
    )
    XCTAssertNil(
      HUDEdgeFeedback.pull(for: keyUp, startingLevel: 1, resultingLevel: 1)
    )
  }

  func testUnknownAndUnsupportedEventsPassThrough() {
    let unknown = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 99, state: 0xA),
      modifierFlags: []
    )
    XCTAssertNil(unknown)
    XCTAssertFalse(MediaKeyRouting.shouldConsume(unknown, deviceCanHandle: true))

    let known = MediaKeyDecoder.decode(
      subtype: 8,
      data1: data1(keyCode: 0, state: 0xA),
      modifierFlags: []
    )
    XCTAssertFalse(MediaKeyRouting.shouldConsume(known, deviceCanHandle: false))
    XCTAssertEqual(MediaKeyRouting.control(for: known!), .volume)
  }

  private func data1(keyCode: Int, state: Int) -> Int {
    (keyCode << 16) | (state << 8)
  }
}

final class VolumeLogicTests: XCTestCase {
  func testClampingPercentageAndFillGeometry() {
    XCTAssertEqual(VolumeMath.clamped(-1), 0)
    XCTAssertEqual(VolumeMath.clamped(2), 1)
    XCTAssertEqual(VolumeMath.percentage(for: 0.734, isMuted: false), 73)
    XCTAssertEqual(VolumeMath.percentage(for: 0.734, isMuted: true), 0)
    XCTAssertEqual(VolumeMath.fillHeight(volumePercent: 50, totalHeight: 562), 281)
    XCTAssertEqual(VolumeMath.fillHeight(volumePercent: 120, totalHeight: 562), 562)
    XCTAssertEqual(
      VolumeMath.volume(byDraggingFrom: 0.6, verticalDelta: 0, height: 562),
      0.6,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      VolumeMath.volume(byDraggingFrom: 0.6, verticalDelta: 56.2, height: 562),
      0.7,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      VolumeMath.volume(byDraggingFrom: 0.95, verticalDelta: 100, height: 562),
      1
    )
    XCTAssertEqual(
      VolumeMath.volume(byDraggingFrom: 0.05, verticalDelta: -100, height: 562),
      0
    )
    XCTAssertEqual(
      VolumeMath.dragRequest(from: 0.5, verticalDelta: 281, height: 562),
      HUDLevelRequest(level: 1, edgePull: nil)
    )
    XCTAssertEqual(
      VolumeMath.dragRequest(from: 0.5, verticalDelta: 300, height: 562),
      HUDLevelRequest(level: 1, edgePull: .upper)
    )
    XCTAssertEqual(
      VolumeMath.dragRequest(from: 0.5, verticalDelta: -300, height: 562),
      HUDLevelRequest(level: 0, edgePull: .lower)
    )
    XCTAssertEqual(VolumeMath.scrollAdjustment(deltaY: 15, isPrecise: true), 0.05)
    XCTAssertEqual(
      VolumeMath.scrollAdjustment(deltaY: -1, isPrecise: false),
      -VolumeAction.normalStep
    )
  }

  func testBrightnessAdjustmentAndHUDPercentage() {
    XCTAssertEqual(BrightnessMath.applying(.increase(step: 0.1), to: 0.95), 1)
    XCTAssertEqual(BrightnessMath.applying(.decrease(step: 0.2), to: 0.1), 0)
    XCTAssertEqual(BrightnessMath.applying(.set(level: 0.427), to: 0), 0.427)
    XCTAssertEqual(HUDSnapshot(control: .displayBrightness, level: 0.734).percentage, 73)
  }

  func testBetterDisplayOSDParsing() {
    let payload = """
      {"displayID":1234,"systemIconID":1,"controlTarget":"combinedBrightness",\
      "value":42,"maxValue":100}
      """
    XCTAssertEqual(
      BetterDisplayOSDParser.snapshot(from: payload),
      HUDSnapshot(control: .displayBrightness, level: 0.42, targetDisplayID: 1234)
    )
    XCTAssertNil(
      BetterDisplayOSDParser.snapshot(
        from: "{\"systemIconID\":3,\"value\":0.5,\"maxValue\":1}"
      )
    )
  }

  func testHoverPreventsHUDDismissal() {
    XCTAssertFalse(
      HUDDismissalPolicy.shouldDismiss(isHovering: true, pointerInsidePanel: true)
    )
    XCTAssertFalse(
      HUDDismissalPolicy.shouldDismiss(isHovering: false, pointerInsidePanel: true)
    )
    XCTAssertTrue(
      HUDDismissalPolicy.shouldDismiss(isHovering: false, pointerInsidePanel: false)
    )
  }

  func testEventTapPriorityReassertionPolicy() {
    XCTAssertFalse(
      EventTapPriorityPolicy.shouldReassert(
        lastObservedAt: 9.8,
        lastReassertedAt: nil,
        now: 10
      )
    )
    XCTAssertTrue(
      EventTapPriorityPolicy.shouldReassert(
        lastObservedAt: 9,
        lastReassertedAt: nil,
        now: 10
      )
    )
    XCTAssertFalse(
      EventTapPriorityPolicy.shouldReassert(
        lastObservedAt: nil,
        lastReassertedAt: 9,
        now: 10,
        force: true
      )
    )
    XCTAssertTrue(
      EventTapPriorityPolicy.shouldReassert(
        lastObservedAt: 9.9,
        lastReassertedAt: 7,
        now: 10,
        force: true
      )
    )
  }

  func testHUDLevelHistorySeparatesControlsOnlyAfterDismissal() {
    var history = HUDLevelHistory()

    XCTAssertEqual(
      history.transition(
        for: .volume,
        target: 50,
        isHUDActive: false,
        displayedPercentage: 0
      ),
      HUDLevelTransition(baseline: 50, target: 50)
    )
    _ = history.transition(
      for: .displayBrightness,
      target: 80,
      isHUDActive: false,
      displayedPercentage: 50
    )

    XCTAssertEqual(
      history.transition(
        for: .volume,
        target: 56,
        isHUDActive: false,
        displayedPercentage: 80
      ),
      HUDLevelTransition(baseline: 50, target: 56)
    )
    XCTAssertEqual(
      history.transition(
        for: .displayBrightness,
        target: 85,
        isHUDActive: true,
        displayedPercentage: 56
      ),
      HUDLevelTransition(baseline: 56, target: 85)
    )
  }

  @MainActor
  func testDismissalTimerContinuesDuringEventTracking() {
    var didFire = false
    let timer = HUDDismissalTimer.schedule(after: 0.01) {
      didFire = true
    }
    let deadline = Date(timeIntervalSinceNow: 0.25)

    while !didFire, Date() < deadline {
      _ = RunLoop.main.run(mode: .eventTracking, before: deadline)
    }

    timer.invalidate()
    XCTAssertTrue(didFire)
  }

  func testVolumeControlSelectionPrecedence() {
    XCTAssertEqual(
      VolumeControlSelection.select(
        virtualMainWritable: true,
        masterWritable: true,
        writableChannels: [1, 2]
      ),
      .virtualMain
    )
    XCTAssertEqual(
      VolumeControlSelection.select(
        virtualMainWritable: false,
        masterWritable: true,
        writableChannels: [1, 2]
      ),
      .master
    )
    XCTAssertEqual(
      VolumeControlSelection.select(
        virtualMainWritable: false,
        masterWritable: false,
        writableChannels: [1, 2]
      ),
      .channels([1, 2])
    )
    XCTAssertEqual(
      VolumeControlSelection.select(
        virtualMainWritable: false,
        masterWritable: false,
        writableChannels: []
      ),
      .unsupported
    )
  }

  func testNativeMuteAutoUnmutesBeforeAdjustment() {
    let result = VolumeStateReducer.apply(
      .increase(step: VolumeAction.normalStep),
      volume: 0.5,
      isMuted: true,
      rememberedVolume: nil,
      usesNativeMute: true
    )
    XCTAssertFalse(result.isMuted)
    XCTAssertEqual(result.volume, 0.5625)
  }

  func testDirectManipulationClampsAndUnmutes() {
    let result = VolumeStateReducer.apply(
      .set(volume: 1.4),
      volume: 0,
      isMuted: true,
      rememberedVolume: 0.5,
      usesNativeMute: false
    )
    XCTAssertEqual(result, VolumeMutation(volume: 1, isMuted: false, rememberedVolume: nil))
  }

  func testEmulatedMuteRemembersAndRestoresVolume() {
    let muted = VolumeStateReducer.apply(
      .toggleMute,
      volume: 0.73,
      isMuted: false,
      rememberedVolume: nil,
      usesNativeMute: false
    )
    XCTAssertEqual(muted, VolumeMutation(volume: 0, isMuted: true, rememberedVolume: 0.73))

    let restored = VolumeStateReducer.apply(
      .toggleMute,
      volume: muted.volume,
      isMuted: muted.isMuted,
      rememberedVolume: muted.rememberedVolume,
      usesNativeMute: false
    )
    XCTAssertEqual(restored, VolumeMutation(volume: 0.73, isMuted: false, rememberedVolume: nil))
  }

  func testAdjustingEmulatedMuteRestoresThenChanges() {
    let result = VolumeStateReducer.apply(
      .decrease(step: VolumeAction.normalStep),
      volume: 0,
      isMuted: true,
      rememberedVolume: 0.5,
      usesNativeMute: false
    )
    XCTAssertEqual(result, VolumeMutation(volume: 0.4375, isMuted: false, rememberedVolume: nil))
  }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
  func testDefaultsAndPersistence() {
    let suite = "ModaTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = SettingsStore(defaults: defaults)
    XCTAssertTrue(first.shouldOpenSettingsOnLaunch)
    XCTAssertTrue(first.consumeFirstLaunchSettingsRequest())
    XCTAssertFalse(first.consumeFirstLaunchSettingsRequest())
    XCTAssertTrue(first.isEnabled)
    XCTAssertTrue(first.isVolumeEnabled)
    XCTAssertTrue(first.isDisplayBrightnessEnabled)
    XCTAssertTrue(first.isKeyboardBrightnessEnabled)
    XCTAssertEqual(first.dismissDelay, 1.5)

    first.isEnabled = false
    first.isVolumeEnabled = false
    first.isDisplayBrightnessEnabled = false
    first.isKeyboardBrightnessEnabled = false
    first.dismissDelay = 2.3

    let second = SettingsStore(defaults: defaults)
    XCTAssertFalse(second.shouldOpenSettingsOnLaunch)
    XCTAssertFalse(second.isEnabled)
    XCTAssertFalse(second.isVolumeEnabled)
    XCTAssertFalse(second.isDisplayBrightnessEnabled)
    XCTAssertFalse(second.isKeyboardBrightnessEnabled)
    XCTAssertEqual(second.dismissDelay, 2.3, accuracy: 0.001)
    XCTAssertTrue(second.enabledControls.isEmpty)
  }

  func testDismissDelayIsClamped() {
    let suite = "ModaTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = SettingsStore(defaults: defaults)
    store.dismissDelay = 12
    XCTAssertEqual(store.dismissDelay, 5)
    store.dismissDelay = 0
    XCTAssertEqual(store.dismissDelay, 0.5)
  }
}
