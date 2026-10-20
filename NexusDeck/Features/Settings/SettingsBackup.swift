import SwiftUI
import ServiceManagement

// MARK: Backup

struct BackupPage: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deck: DeckController
    @EnvironmentObject var audio: AudioService
    @State private var selected = 0
    @State private var message: String?

    var body: some View {
        SectionCard(title: "Backup e ripristino del file di configurazione") {
            Text("Salva la configurazione di NexusDeck su questo Mac per poterla ripristinare in futuro.").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            Text(message ?? lastBackupText).font(.system(size: 13)).foregroundStyle(Theme.textMid)
            HStack(spacing: 12) {
                FlatButton(title: "Esegui backup", width: 134) { do { try store.backupSlot(selected); message = "Backup salvato nello slot \(selected + 1)" } catch { message = error.localizedDescription } }
                FlatButton(title: "Ripristina backup", width: 134) {
                    do { try store.restoreSlot(selected); deck.profileChanged(); audio.applyAll(); message = "Configurazione ripristinata" } catch { message = "Lo slot selezionato è vuoto" }
                }
                .disabled(store.slotDate(selected) == nil)
            }
            Text("Seleziona prima lo slot da salvare o ripristinare").font(.system(size: 13)).foregroundStyle(Theme.textMid)
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    Button { selected = i } label: {
                        HStack(spacing: 24) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 15))
                            Text(store.slotDate(i).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Nessuna data")
                                .font(.system(size: 14))
                                .foregroundStyle(selected == i ? Theme.accent : Theme.textMid)
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Theme.field).clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var lastBackupText: String {
        let dates = (0..<5).compactMap { store.slotDate($0) }
        guard let last = dates.max() else { return "Nessun backup salvato su questo Mac" }
        return "Ultimo backup: \(last.formatted(date: .abbreviated, time: .shortened))"
    }
}
