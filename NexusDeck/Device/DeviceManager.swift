import Foundation
import IOKit.hid
import Combine

enum ConnectionState: Equatable {
    case disconnected
    case connected(DeviceInfo)
    case error(String)

    var isConnected: Bool { if case .connected = self { return true } else { return false } }
}

struct RawReport: Identifiable {
    let id = UUID()
    let date = Date()
    let bytes: Data

    var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

/// Watches for controller hot-plug and owns the open HID device.
@MainActor
final class DeviceManager: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var reportLog: [RawReport] = []
    @Published var isMonitoring = false

    /// Fired for every input report coming from the controller.
    let inputReports = PassthroughSubject<Data, Never>()
    /// Fired when a controller is attached and opened.
    let didConnect = PassthroughSubject<HIDDevice, Never>()

    private(set) var device: HIDDevice?
    private var manager: IOHIDManager?

    func start() {
        guard manager == nil else { return }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: USBIDs.vendor,
            kIOHIDPrimaryUsagePageKey: USBIDs.controlUsagePage,
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, dev in
            guard let ctx else { return }
            let me = Unmanaged<DeviceManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.attach(dev) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, dev in
            guard let ctx else { return }
            let me = Unmanaged<DeviceManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.detach(dev) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            state = .error(String(localized: "Impossibile aprire il gestore HID (codice \(r)). Concedi 'Monitoraggio input' in Impostazioni di Sistema."))
        }
        manager = mgr
    }

    private func attach(_ dev: IOHIDDevice) {
        guard device == nil else { return }
        let pid = dev.intProperty(kIOHIDProductIDKey)
        let name = dev.stringProperty(kIOHIDProductKey)
        let model: DeviceModel
        switch pid {
        case 0x1310: model = .ax310
        case 0x1130: model = .ax130
        default: model = name.contains("310") ? .ax310 : .unknown
        }
        let info = DeviceInfo(
            model: model,
            productName: name,
            vendorID: dev.intProperty(kIOHIDVendorIDKey),
            productID: pid,
            serialNumber: dev.stringProperty(kIOHIDSerialNumberKey),
            locationID: dev.intProperty(kIOHIDLocationIDKey),
            maxInputReportSize: dev.intProperty(kIOHIDMaxInputReportSizeKey),
            maxOutputReportSize: dev.intProperty(kIOHIDMaxOutputReportSizeKey),
            maxFeatureReportSize: dev.intProperty(kIOHIDMaxFeatureReportSizeKey)
        )
        let hid = HIDDevice(device: dev, info: info)
        guard hid.open() else {
            state = .error(String(localized: "Dispositivo trovato ma non apribile (forse in uso da un'altra app)."))
            return
        }
        hid.onInputReport = { [weak self] data in
            Task { @MainActor in self?.handle(data) }
        }
        device = hid
        state = .connected(info)
        didConnect.send(hid)
    }

    private func detach(_ dev: IOHIDDevice) {
        guard let d = device, d.device == dev else { return }
        device = nil
        state = .disconnected
    }

    private func handle(_ data: Data) {
        inputReports.send(data)
        if isMonitoring {
            reportLog.insert(RawReport(bytes: data), at: 0)
            if reportLog.count > 500 { reportLog.removeLast(reportLog.count - 500) }
        }
    }

    func clearLog() { reportLog.removeAll() }

    func updateFirmwareVersion(_ v: String) {
        if case .connected(var info) = state {
            info.firmwareVersion = v
            state = .connected(info)
        }
    }
}
