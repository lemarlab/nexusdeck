import SwiftUI

/// Sidebar page "Illuminazione": custom lighting and interactive lighting (live / recording).
struct LightingPage: View {
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                seg("Personalizzata", 0)
                seg("Interattiva", 1)
            }
            .padding(2)
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 320)
            .padding(.top, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if tab == 0 { CustomLightingPage() } else { InteractiveLightingPage() }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func seg(_ t: LocalizedStringKey, _ i: Int) -> some View {
        let on = tab == i
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = i } } label: {
            Text(t).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.text : Theme.textDim)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(on ? Theme.card : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
