import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: locs)! }

// macOS icon grid: 824×824 rounded square centred, with soft drop shadow.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: c(0, 0, 0, 0.45))
ctx.addPath(tilePath); ctx.setFillColor(c(0.1, 0.1, 0.11)); ctx.fillPath()
ctx.restoreGState()

// Background: graphite gradient.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(grad([c(0.24, 0.24, 0.26), c(0.07, 0.07, 0.08)], [0, 1]),
                       start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
// Warm glow behind the knob.
let ctr = CGPoint(x: S / 2, y: S / 2 - 6)
ctx.drawRadialGradient(grad([c(1, 0.55, 0.1, 0.22), c(1, 0.55, 0.1, 0)], [0, 1]),
                       startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: 400, options: [])
ctx.restoreGState()
// Subtle top highlight on the tile edge.
ctx.saveGState()
ctx.addPath(tilePath); ctx.setStrokeColor(c(1, 1, 1, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
ctx.restoreGState()

// LED ring: 270° arc of rounded segments, lit from the start up to ~75%.
let ringR: CGFloat = 300
let segments = 24
let startA = CGFloat.pi * 1.25, sweep = CGFloat.pi * 1.5
let lit = 17
for i in 0..<segments {
    let t = CGFloat(i) / CGFloat(segments - 1)
    let a = startA - sweep * t
    let p0 = CGPoint(x: ctr.x + cos(a) * (ringR - 34), y: ctr.y + sin(a) * (ringR - 34))
    let p1 = CGPoint(x: ctr.x + cos(a) * (ringR + 34), y: ctr.y + sin(a) * (ringR + 34))
    ctx.saveGState()
    ctx.setLineCap(.round); ctx.setLineWidth(26)
    if i < lit {
        // Orange → amber along the arc, with glow.
        let k = CGFloat(i) / CGFloat(lit)
        let col = c(1, 0.42 + 0.28 * k, 0.05 + 0.1 * k)
        ctx.setShadow(offset: .zero, blur: 28, color: c(1, 0.5, 0.05, 0.9))
        ctx.setStrokeColor(col)
    } else {
        ctx.setStrokeColor(c(1, 1, 1, 0.09))
    }
    ctx.move(to: p0); ctx.addLine(to: p1); ctx.strokePath()
    ctx.restoreGState()
}

// Knob: dark body with drop shadow, brushed top, bevel.
let knobR: CGFloat = 215
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: c(0, 0, 0, 0.7))
ctx.addEllipse(in: CGRect(x: ctr.x - knobR, y: ctr.y - knobR, width: 2 * knobR, height: 2 * knobR))
ctx.setFillColor(c(0.13, 0.13, 0.14)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: ctr.x - knobR, y: ctr.y - knobR, width: 2 * knobR, height: 2 * knobR)); ctx.clip()
ctx.drawLinearGradient(grad([c(0.42, 0.42, 0.45), c(0.12, 0.12, 0.13)], [0, 1]),
                       start: CGPoint(x: ctr.x, y: ctr.y + knobR), end: CGPoint(x: ctr.x, y: ctr.y - knobR), options: [])
ctx.restoreGState()
let topR = knobR - 26
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: ctr.x - topR, y: ctr.y - topR, width: 2 * topR, height: 2 * topR)); ctx.clip()
ctx.drawLinearGradient(grad([c(0.30, 0.30, 0.32), c(0.17, 0.17, 0.18)], [0, 1]),
                       start: CGPoint(x: ctr.x, y: ctr.y + topR), end: CGPoint(x: ctr.x, y: ctr.y - topR), options: [])
// Fine concentric "brushed" rings.
for r in stride(from: CGFloat(8), to: topR, by: 7) {
    ctx.addEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: 2 * r, height: 2 * r))
    ctx.setStrokeColor(c(1, 1, 1, r.truncatingRemainder(dividingBy: 14) < 7 ? 0.025 : 0.0)); ctx.setLineWidth(2); ctx.strokePath()
}
// Specular highlight.
ctx.drawRadialGradient(grad([c(1, 1, 1, 0.16), c(1, 1, 1, 0)], [0, 1]),
                       startCenter: CGPoint(x: ctr.x - 50, y: ctr.y + 90), startRadius: 0,
                       endCenter: CGPoint(x: ctr.x - 50, y: ctr.y + 90), endRadius: 200, options: [])
ctx.restoreGState()
ctx.addEllipse(in: CGRect(x: ctr.x - topR, y: ctr.y - topR, width: 2 * topR, height: 2 * topR))
ctx.setStrokeColor(c(1, 1, 1, 0.08)); ctx.setLineWidth(2); ctx.strokePath()

// Indicator: glowing orange pill pointing at the end of the lit arc.
let ia = startA - sweep * CGFloat(lit - 1) / CGFloat(segments - 1)
let q0 = CGPoint(x: ctr.x + cos(ia) * 95, y: ctr.y + sin(ia) * 95)
let q1 = CGPoint(x: ctr.x + cos(ia) * 160, y: ctr.y + sin(ia) * 160)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 22, color: c(1, 0.55, 0.1, 1))
ctx.setLineCap(.round); ctx.setLineWidth(24); ctx.setStrokeColor(c(1, 0.62, 0.15))
ctx.move(to: q0); ctx.addLine(to: q1); ctx.strokePath()
ctx.restoreGState()

let img = ctx.makeImage()!
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
