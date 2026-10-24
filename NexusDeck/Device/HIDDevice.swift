import Foundation
import IOKit
import IOKit.hid

/// Hardware models supported by the controller protocol.
enum DeviceModel: String, Codable, CaseIterable {
    case ax310 = "AX310"
    case ax130 = "AX130"
    case unknown = "Unknown"

    /// Touch panel grid (columns x rows) and physical function keys.
    var gridColumns: Int { 5 }
    var gridRows: Int { 4 }
    var functionKeyCount: Int { self == .ax130 ? 0 : 4 }
    var knobCount: Int { 6 }
}

struct DeviceInfo: Equatable {
    var model: DeviceModel
    var productName: String
    var vendorID: Int
    var productID: Int
    var serialNumber: String
    var locationID: Int
    var maxInputReportSize: Int
    var maxOutputReportSize: Int
    var maxFeatureReportSize: Int
    var firmwareVersion: String = ""
}

enum USBIDs {
    static let vendor = 0x07CA
    /// Vendor-defined usage page of the control interface.
    static let controlUsagePage = 0xFFA0
    static let ax310Control = 0x1310
}

/// Thin wrapper around a single opened IOHIDDevice.
final class HIDDevice {
    let device: IOHIDDevice
    let info: DeviceInfo
    private var inputBuffer: UnsafeMutablePointer<UInt8>
    private let inputBufferSize: Int
    var onInputReport: ((Data) -> Void)?

    init(device: IOHIDDevice, info: DeviceInfo) {
        self.device = device
        self.info = info
        inputBufferSize = max(info.maxInputReportSize, 64)
        inputBuffer = .allocate(capacity: inputBufferSize)
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deallocate()
    }

    func open() -> Bool {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, inputBufferSize, { ctx, result, _, _, _, report, length in
            guard let ctx, result == kIOReturnSuccess else { return }
            let me = Unmanaged<HIDDevice>.fromOpaque(ctx).takeUnretainedValue()
            me.onInputReport?(Data(bytes: report, count: length))
        }, ctx)
        return true
    }

    // The control interface has no report IDs: payloads are sent as-is with report ID 0.

    @discardableResult
    func setFeature(_ bytes: [UInt8]) -> IOReturn {
        return bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
        }
    }

    func getFeature(length: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: length)
        var len = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &len)
        }
        return r == kIOReturnSuccess ? Array(buf.prefix(len)) : nil
    }

    @discardableResult
    func setOutput(_ bytes: [UInt8]) -> IOReturn {
        return bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
    }
}

extension IOHIDDevice {
    func intProperty(_ key: String) -> Int {
        (IOHIDDeviceGetProperty(self, key as CFString) as? NSNumber)?.intValue ?? 0
    }
    func stringProperty(_ key: String) -> String {
        IOHIDDeviceGetProperty(self, key as CFString) as? String ?? ""
    }
}

