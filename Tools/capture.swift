import Foundation
import IOKit.hid

// Logs raw input reports from the R2 scroll ring (VID 0x05D6, PID 0x022C).
let vid = 0x05D6, pid = 0x022C
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid] as CFDictionary)

var buffers: [UnsafeMutablePointer<UInt8>] = []
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    buffers.append(buf)
    IOHIDDeviceRegisterInputReportCallback(device, buf, 64, { _, _, _, _, reportID, report, length in
        let bytes = (0..<length).map { String(format: "%02x", report[$0]) }.joined(separator: " ")
        let t = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        print("\(t) id=\(reportID) len=\(length): \(bytes)")
        fflush(stdout)
    }, nil)
    print("matched device"); fflush(stdout)
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("open result: \(String(format: "0x%08x", r))"); fflush(stdout)
CFRunLoopRun()
