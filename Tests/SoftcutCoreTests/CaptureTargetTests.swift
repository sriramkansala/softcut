import XCTest
@testable import SoftcutCore

final class CaptureTargetTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testARectangleBecomesFractionsOfTheDisplay() {
        let crop = CaptureTarget.crop(for: CGRect(x: 400, y: 250, width: 800, height: 500), inDisplay: display)
        XCTAssertEqual(crop.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(crop.y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(crop.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(crop.height, 0.5, accuracy: 1e-9)
    }

    func testASecondDisplayIsMeasuredFromItsOwnCorner() {
        // A display placed to the right of the main one starts at x = 1600.
        let second = CGRect(x: 1600, y: 0, width: 1920, height: 1080)
        let crop = CaptureTarget.crop(for: CGRect(x: 1600 + 480, y: 270, width: 960, height: 540), inDisplay: second)
        XCTAssertEqual(crop.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(crop.y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(crop.width, 0.5, accuracy: 1e-9)
    }

    func testPartOffTheDisplayIsCutOffAndNothingOnItIsTheWholeDisplay() {
        let hanging = CaptureTarget.crop(for: CGRect(x: 1400, y: -100, width: 400, height: 400), inDisplay: display)
        XCTAssertEqual(hanging.x, 0.875, accuracy: 1e-9)
        XCTAssertEqual(hanging.y, 0, accuracy: 1e-9)
        XCTAssertEqual(hanging.width, 0.125, accuracy: 1e-9)
        XCTAssertEqual(hanging.height, 0.3, accuracy: 1e-9)

        XCTAssertTrue(CaptureTarget.crop(for: CGRect(x: 5000, y: 5000, width: 100, height: 100), inDisplay: display).isFull)
        XCTAssertTrue(CaptureTarget.crop(for: CGRect(x: 0, y: 0, width: 100, height: 100), inDisplay: .zero).isFull)
    }

    func testTheWindowInFrontIsTheOneUnderThePoint() {
        let back = WindowInfo(id: 1, ownerName: "Notes", title: "Shopping", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), ownerPID: 10)
        let front = WindowInfo(id: 2, ownerName: "Safari", title: "", bounds: CGRect(x: 400, y: 300, width: 800, height: 600), ownerPID: 11)
        // Front to back, like the system's list.
        let windows = [front, back]
        XCTAssertEqual(WindowCatalog.window(at: CGPoint(x: 500, y: 400), in: windows)?.id, 2, "where they overlap, the front one")
        XCTAssertEqual(WindowCatalog.window(at: CGPoint(x: 100, y: 100), in: windows)?.id, 1)
        XCTAssertNil(WindowCatalog.window(at: CGPoint(x: 1500, y: 900), in: windows))
        XCTAssertEqual(front.label, "Safari")
        XCTAssertEqual(back.label, "Notes — Shopping")
    }

    private func entry(layer: Int = 0, alpha: Double = 1, width: Double = 640, height: Double = 480, pid: Int32 = 99, number: UInt32 = 7) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: number), kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowAlpha as String: NSNumber(value: alpha), kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowOwnerName as String: "App", kCGWindowName as String: "Doc",
         kCGWindowBounds as String: CGRect(x: 10, y: 20, width: width, height: height).dictionaryRepresentation]
    }

    func testOnlyOrdinaryWindowsAreOffered() {
        XCTAssertEqual(WindowCatalog.parse(entry(), excludingPID: nil)?.title, "Doc")
        XCTAssertEqual(WindowCatalog.parse(entry(), excludingPID: nil)?.bounds, CGRect(x: 10, y: 20, width: 640, height: 480))
        XCTAssertNil(WindowCatalog.parse(entry(layer: 25), excludingPID: nil), "menu bar and system layers")
        XCTAssertNil(WindowCatalog.parse(entry(alpha: 0), excludingPID: nil), "invisible windows")
        XCTAssertNil(WindowCatalog.parse(entry(width: 30, height: 30), excludingPID: nil), "badges and tooltips")
        XCTAssertNil(WindowCatalog.parse(entry(pid: 42), excludingPID: 42), "Softcut's own bar and overlays")
        XCTAssertNotNil(WindowCatalog.parse(entry(pid: 42), excludingPID: 43))
    }

    func testTheRealWindowListDoesNotIncludeThisProcess() {
        let windows = WindowCatalog.onScreen()
        XCTAssertFalse(windows.contains { $0.ownerPID == ProcessInfo.processInfo.processIdentifier })
        for window in windows { XCTAssertGreaterThanOrEqual(window.bounds.width, WindowCatalog.minimumSide) }
    }

    func testTheMainDisplayCanBeFoundForAnAreaOnIt() {
        let main = CGDisplayBounds(CGMainDisplayID())
        let rect = CGRect(x: main.minX + 100, y: main.minY + 100, width: 400, height: 300)
        let target = CaptureTarget.area(rect)
        XCTAssertEqual(target.displayID, CGMainDisplayID())
        XCTAssertNil(target.windowID)
        XCTAssertEqual(try XCTUnwrap(target.crop).width, 400 / main.width, accuracy: 1e-6)

        let window = WindowInfo(id: 55, ownerName: "App", title: "", bounds: rect, ownerPID: 1)
        XCTAssertEqual(CaptureTarget.window(window).windowID, 55)
    }

    func testRecordingOptionsDefaultToTheWholeDisplayAndTheSystemDevices() {
        let options = RecordingOptions(outputFolder: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertNil(options.windowID)
        XCTAssertNil(options.cameraID)
        XCTAssertNil(options.microphoneID)
    }
}

final class DeviceChoiceTests: XCTestCase {
    private let devices = [InputDevice(id: "a", name: "Built-in"), InputDevice(id: "b", name: "USB")]

    func testOffMeansNoDevice() {
        XCTAssertNil(DeviceChoice(enabled: false, chosen: "a").resolved(in: devices))
    }

    func testTheChosenOneIsUsedWhileConnectedElseTheFirst() {
        XCTAssertEqual(DeviceChoice(enabled: true, chosen: "b").resolved(in: devices), "b")
        XCTAssertEqual(DeviceChoice(enabled: true, chosen: "gone").resolved(in: devices), "a")
        XCTAssertEqual(DeviceChoice(enabled: true, chosen: nil).resolved(in: devices), "a")
        XCTAssertNil(DeviceChoice(enabled: true, chosen: "a").resolved(in: []))
    }

    func testPickingAndTurningOffRemembersTheLastDevice() {
        var choice = DeviceChoice(enabled: false, chosen: nil)
        choice.select("b")
        XCTAssertTrue(choice.enabled)
        XCTAssertEqual(choice.chosen, "b")
        choice.select(nil)
        XCTAssertFalse(choice.enabled)
        XCTAssertEqual(choice.chosen, "b", "turned back on later, it is the same device")
    }
}
