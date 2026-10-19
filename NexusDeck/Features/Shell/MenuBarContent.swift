import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var devices: DeviceManager
    var body: some View {
        switch devices.state {
        case .connected(let info): Text("Collegato: \(info.productName)")
        case .disconnected: Text("Nessun dispositivo collegato")
        case .error(let e): Text(e)
        }
        Divider()
        Button("Esci") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
