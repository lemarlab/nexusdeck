import SwiftUI

// MARK: - Shared vertical slider card

/// Card with a title, a vertical slider and a numeric field with stepper (as in "Microphone Effects").
struct VSliderCard: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String
    var decimals = 0
    var width: CGFloat = 119
    var height: CGFloat = 300
    var enabled = true

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(height: 40, alignment: .top)
                .padding(.top, 14)
            Spacer(minLength: 8)
            VerticalTrack(value: $value, range: range, step: step)
                .frame(width: 24, height: 160)
            Spacer(minLength: 10)
            HStack(spacing: 4) {
                Text(decimals == 0 ? "\(Int(value.rounded()))" : String(format: "%.\(decimals)f", value))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .frame(width: 50, height: 24).background(Theme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(spacing: 2) {
                    Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "arrowtriangle.up.fill") }
                    Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "arrowtriangle.down.fill") }
                }
                .font(.system(size: 7)).buttonStyle(.plain).foregroundStyle(Theme.textDim)
                Text(unit).font(.system(size: 10)).foregroundStyle(Theme.textDim).frame(width: 20, alignment: .leading)
            }
            .padding(.bottom, 14)
        }
        .frame(width: width, height: height)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
    }
}

struct VerticalTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        GeometryReader { g in
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.track).frame(width: 5)
                Capsule().fill(Theme.accent).frame(width: 5, height: max(0, g.size.height * f))
                Circle().fill(.white).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .offset(y: -g.size.height * f + 9)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let p = 1 - min(max(v.location.y / g.size.height, 0), 1)
                let raw = range.lowerBound + Double(p) * (range.upperBound - range.lowerBound)
                value = (raw / step).rounded() * step
            })
        }
    }
}

