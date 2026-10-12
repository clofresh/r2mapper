import CoreGraphics
import Foundation

/// Swallows the events macOS generates from the ring itself (touch gestures from its fake
/// touchscreen, Volume Up from its Home button) so only our mapped actions take effect.
/// Needs Accessibility permission; `start()` returns false until it's granted.
final class EventFilter {
    /// Undocumented CGEvent field holding the registry ID of the IOHIDService that produced the event.
    static let senderIDField = CGEventField(rawValue: 87)!

    var shouldDrop: (UInt64) -> Bool = { _ in false }
    var debug = false
    private var tap: CFMachPort?

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // Every event type: the ring's events are identified by sender, not type.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask.max, callback: { _, type, event, ctx in
            let filter = Unmanaged<EventFilter>.fromOpaque(ctx!).takeUnretainedValue()
            return filter.handle(type: type, event: event)
        }, userInfo: ctx) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let sender = UInt64(bitPattern: event.getIntegerValueField(EventFilter.senderIDField))
        if sender != 0 && shouldDrop(sender) {
            if debug { print("dropped event type \(type.rawValue) from ring"); fflush(stdout) }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
