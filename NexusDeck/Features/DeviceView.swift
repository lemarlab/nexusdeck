import SwiftUI

struct DeviceView: View {
    @EnvironmentObject var devices: DeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Dispositivo") {
                switch devices.state {
                case .connected(let info):
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        row("Modello", info.model.rawValue)
                        row("Nome", info.productName)
                        row("VID:PID", String(format: "%04X:%04X", info.vendorID, info.productID))
                        row("Seriale", info.serialNumber.isEmpty ? "—" : info.serialNumber)
                        row("Firmware", info.firmwareVersion.isEmpty ? "—" : info.firmwareVersion)
                        row("Report (in/out/feature)", "\(info.maxInputReportSize) / \(info.maxOutputReportSize) / \(info.maxFeatureReportSize) B")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .disconnected:
                    Text("Collega il controller via USB.").foregroundStyle(.secondary)
                case .error(let msg):
                    Text(msg).foregroundStyle(.red)
                }
            }

            AudioBridgeBox()

            GroupBox {
                VStack(alignment: .leading) {
                    HStack {
                        Toggle("Monitor report HID", isOn: $devices.isMonitoring)
                        Spacer()
                        Button("Pulisci") { devices.clearLog() }
                    }
                    List(devices.reportLog) { r in
                        HStack(alignment: .top) {
                            Text(r.date, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.secondary)
                            Text(r.hex).textSelection(.enabled)
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                    .frame(minHeight: 260)
                }
            } label: {
                Text("Debug")
            }
        }
        .padding()
        .navigationTitle("Dispositivo")
    }

    private func row(_ k: LocalizedStringKey, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }
}

struct AudioBridgeBox: View {
    @EnvironmentObject var bridge: AudioBridge
    @State private var message: String?

    var body: some View {
        GroupBox("Audio") {
            HStack {
                switch bridge.status {
                case .running: Label("Dispositivi audio attivi (Creator Mix, Audience Mix, Chat Mic, System, Game, Chat)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .missingPlugIn: Label("Plug-in audio NexusDeck non installato", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .missingInterface: Label("Interfaccia audio USB del controller non trovata", systemImage: "cable.connector.slash").foregroundStyle(.secondary)
                case .failed(let e): Label(e, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                case .idle: Text("Non avviato").foregroundStyle(.secondary)
                }
                Spacer()
                if bridge.status == .missingPlugIn || !bridge.isPlugInInstalled {
                    Button("Installa driver audio…") { message = bridge.installPlugIn() }
                } else {
                    Menu("Driver audio") {
                        Button("Reinstalla/aggiorna…") { message = bridge.installPlugIn() }
                        Button("Disinstalla…", role: .destructive) { message = bridge.uninstallPlugIn() }
                    }
                    .fixedSize()
                }
                Button("Riavvia audio") { bridge.stop(); bridge.start() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
    }
}
