import Foundation
import IOKit.hid

enum RingButton: String, CaseIterable, Codable {
    case up, down, left, right, ok, home
}

/// Reads the R2 scroll ring's raw HID reports and turns them into button presses.
///
/// macOS only lets root seize a device that presents a keyboard interface, so the ring's
/// own events still reach the system; `EventFilter` drops them using `senderIDs`.
///
/// What the ring sends (from its report descriptor + captures):
/// - Report 2 (digitizer): [id, flags, xLo, xHi, yLo, yHi], flags bit 0x10 = finger down.
///   Up/Down/Left/Right are synthetic swipes, OK is a tap at the center.
///   Up: Y increases, Down: Y decreases, Left: X increases, Right: X decreases.
/// - Report 4 (consumer): [id, bits]; bit 0 (Volume Up) is the Home button.
final class Ring {
    static let vendorID = 0x05D6
    static let productID = 0x022C

    var onButton: ((RingButton) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var debug = false
    private(set) var connected = false
    /// Registry IDs of the ring's IOHIDEventServices; CGEvents carry these as their sender ID.
    private(set) var senderIDs: Set<UInt64> = []

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var touchStart: (x: Int, y: Int)?
    private var touchLast: (x: Int, y: Int)?
    private var lastConsumerBits: UInt8 = 0
    private var reportBuffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]

    /// Movement (in the ring's 0...2047 coordinate space) below which a touch counts as a tap.
    private let tapThreshold = 150

    func start() -> IOReturn {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Ring.vendorID,
            kIOHIDProductIDKey: Ring.productID,
        ] as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            let ring = Unmanaged<Ring>.fromOpaque(ctx!).takeUnretainedValue()
            ring.attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            let ring = Unmanaged<Ring>.fromOpaque(ctx!).takeUnretainedValue()
            ring.detach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        reportBuffers[device] = buffer
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { ctx, _, _, _, reportID, report, length in
            let ring = Unmanaged<Ring>.fromOpaque(ctx!).takeUnretainedValue()
            ring.handle(reportID: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
        }, ctx)
        setConnected(true)
        // The event service can register a moment after the HID device, so look again shortly.
        refreshSenderIDs()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshSenderIDs() }
    }

    private func detach(_ device: IOHIDDevice) {
        reportBuffers.removeValue(forKey: device)?.deallocate()
        touchStart = nil
        touchLast = nil
        setConnected(!reportBuffers.isEmpty)
    }

    func refreshSenderIDs() {
        let matching = IOServiceMatching("IOHIDEventService") as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = Ring.vendorID
        matching[kIOHIDProductIDKey] = Ring.productID
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var ids: Set<UInt64> = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS { ids.insert(id) }
            IOObjectRelease(service)
        }
        senderIDs = ids
        log("sender IDs: \(ids.map { String($0, radix: 16) })")
    }

    private func setConnected(_ value: Bool) {
        connected = value
        log(value ? "ring connected" : "ring disconnected")
        onConnectionChange?(value)
    }

    private func handle(reportID: UInt32, bytes: [UInt8]) {
        if debug { log("report \(reportID): " + bytes.map { String(format: "%02x", $0) }.joined(separator: " ")) }
        switch reportID {
        case 2 where bytes.count >= 6:
            let down = bytes[1] & 0x10 != 0
            let x = Int(bytes[2]) | Int(bytes[3]) << 8
            let y = Int(bytes[4]) | Int(bytes[5]) << 8
            if down {
                if touchStart == nil { touchStart = (x, y) }
                touchLast = (x, y)
            } else if let start = touchStart {
                let end = touchLast ?? start
                touchStart = nil
                touchLast = nil
                if let button = classify(dx: end.x - start.x, dy: end.y - start.y) { fire(button) }
            }
        case 4 where bytes.count >= 2:
            let bits = bytes[1]
            let pressed = bits & ~lastConsumerBits
            lastConsumerBits = bits
            if pressed & 0x01 != 0 { fire(.home) }
        default:
            break
        }
    }

    private func classify(dx: Int, dy: Int) -> RingButton? {
        if abs(dx) < tapThreshold && abs(dy) < tapThreshold { return .ok }
        if abs(dy) >= abs(dx) { return dy > 0 ? .up : .down }
        return dx > 0 ? .left : .right
    }

    private func fire(_ button: RingButton) {
        log("button: \(button.rawValue)")
        onButton?(button)
    }

    func log(_ message: String) {
        if debug { print(message); fflush(stdout) }
    }
}
