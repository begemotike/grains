// Renders the Grains app icon procedurally: a low heap of golden grains on a charcoal squircle, with an
// ascending time-graph line rising behind it to a glowing gold dot. No text, so it survives 16 px.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat)], alpha: [CGFloat]? = nil) -> CGGradient {
    let colors = stops.enumerated().map { rgb($0.element.0, alpha?[$0.offset] ?? 1) } as CFArray
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: stops.map { $0.1 })!
}
// SplitMix64: deterministic, so the icon is byte-stable across runs.
struct Rand { var s: UInt64; mutating func next() -> CGFloat { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return CGFloat((z ^ (z >> 31)) % 10000) / 10000 } }

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // top-left origin

// macOS icon grid: the artwork sits in an 824-pt squircle centred in the 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 824 * 0.2237, cornerHeight: 824 * 0.2237, transform: nil)

let gold: UInt32 = 0xE2B714, goldLight: UInt32 = 0xF8E27A, goldDark: UInt32 = 0x8C6A06, goldDeep: UInt32 = 0x5A4304
let lineGrey: UInt32 = 0x8A93A3

// Tile drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0x000000, 0.5))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0x161A20)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()

// Background: charcoal, slightly lifted at the upper centre, vignetted towards the rim.
ctx.setFillColor(rgb(0x161A20)); ctx.fill(tile)
ctx.drawRadialGradient(gradient([(0x262C36, 0), (0x161A20, 1)], alpha: [1, 0]),
                       startCenter: CGPoint(x: tile.midX, y: tile.minY + tile.height * 0.42), startRadius: 0,
                       endCenter: CGPoint(x: tile.midX, y: tile.minY + tile.height * 0.42), endRadius: tile.width * 0.62, options: [])
ctx.drawRadialGradient(gradient([(0x000000, 0), (0x000000, 0.62), (0x000000, 1)], alpha: [0, 0, 0.55]),
                       startCenter: CGPoint(x: tile.midX, y: tile.midY), startRadius: 0,
                       endCenter: CGPoint(x: tile.midX, y: tile.midY), endRadius: tile.width * 0.75, options: [])

// Faint baseline grid, like the weekly graph's axis.
ctx.setStrokeColor(rgb(lineGrey, 0.07)); ctx.setLineWidth(3)
for i in 1...3 {
    let y = tile.minY + tile.height * (0.22 + CGFloat(i) * 0.15)
    ctx.move(to: CGPoint(x: tile.minX + 90, y: y)); ctx.addLine(to: CGPoint(x: tile.maxX - 90, y: y)); ctx.strokePath()
}

// Ascending time-graph line, drawn before the heap so the grains sit in front of its start.
let graph: [CGPoint] = [CGPoint(x: 180, y: 700), CGPoint(x: 290, y: 620), CGPoint(x: 380, y: 652),
                        CGPoint(x: 495, y: 510), CGPoint(x: 585, y: 545), CGPoint(x: 700, y: 380), CGPoint(x: 778, y: 300)]
let graphPath = CGMutablePath(); graphPath.addLines(between: graph)
ctx.saveGState()
ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 12, color: rgb(0x000000, 0.55))
ctx.addPath(graphPath); ctx.setStrokeColor(rgb(lineGrey)); ctx.setLineWidth(24); ctx.strokePath()
ctx.restoreGState()
// Warm the last segment towards the dot.
ctx.saveGState()
ctx.addPath(graphPath.copy(strokingWithWidth: 24, lineCap: .round, lineJoin: .round, miterLimit: 10)); ctx.clip()
ctx.drawLinearGradient(gradient([(lineGrey, 0), (lineGrey, 0.62), (gold, 1)], alpha: [0, 0, 0.9]),
                       start: graph[0], end: graph[graph.count - 1], options: [])
ctx.restoreGState()

// Glowing gold dot at the top of the graph.
let dot = graph[graph.count - 1]
ctx.drawRadialGradient(gradient([(gold, 0), (gold, 0.35), (gold, 1)], alpha: [0.55, 0.22, 0]),
                       startCenter: dot, startRadius: 0, endCenter: dot, endRadius: 150, options: [])
let dotR: CGFloat = 46
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: dotR * 2, height: dotR * 2)); ctx.clip()
ctx.drawRadialGradient(gradient([(0xFFF6CC, 0), (goldLight, 0.35), (gold, 0.8), (goldDark, 1)]),
                       startCenter: CGPoint(x: dot.x - 14, y: dot.y - 16), startRadius: 0,
                       endCenter: dot, endRadius: dotR, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// The heap: a solid mound silhouette first (so it reads at 16 px), then individual grains on top.
let heapCX = tile.midX - 10, heapBase: CGFloat = 790, heapHalfW: CGFloat = 310, heapH: CGFloat = 250
func heapTop(_ u: CGFloat) -> CGFloat { heapH * pow(max(0, 1 - u * u), 1.5) }   // u in -1...1
let mound = CGMutablePath()
mound.move(to: CGPoint(x: heapCX - heapHalfW, y: heapBase))
for i in 0...60 {
    let u = -1 + CGFloat(i) / 30
    mound.addLine(to: CGPoint(x: heapCX + u * heapHalfW, y: heapBase - heapTop(u) * 0.93))
}
mound.addQuadCurve(to: CGPoint(x: heapCX - heapHalfW, y: heapBase), control: CGPoint(x: heapCX, y: heapBase + 28))
mound.closeSubpath()
// contact shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: rgb(0x000000, 0.75))
ctx.fillEllipse(in: CGRect(x: heapCX - heapHalfW - 20, y: heapBase - 22, width: (heapHalfW + 20) * 2, height: 50))
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(mound); ctx.clip()
ctx.drawLinearGradient(gradient([(0xC99F10, 0), (goldDark, 0.6), (goldDeep, 1)]), start: CGPoint(x: 0, y: heapBase - heapH), end: CGPoint(x: 0, y: heapBase), options: [])
ctx.restoreGState()

struct Grain { var c: CGPoint; var w: CGFloat; var h: CGFloat; var angle: CGFloat; var tone: CGFloat }
var r = Rand(s: 0x6A41)
var grains: [Grain] = []
while grains.count < 58 {
    let u = r.next() * 2 - 1
    let top = heapTop(u)
    guard top > 22 else { continue }
    // Bias towards the surface so the mound outline is made of grains.
    let depth = pow(r.next(), 0.55)
    let y = heapBase - 16 - (top - 26) * depth
    let x = heapCX + u * (heapHalfW - 26)
    let w = 56 + r.next() * 14, h = 25 + r.next() * 5
    let angle = (r.next() - 0.5) * 1.1 + u * 0.35
    grains.append(Grain(c: CGPoint(x: x, y: y), w: w, h: h, angle: angle, tone: r.next()))
}
// A few grains spilled at the foot of the heap.
for (dx, dy, a) in [(-345.0, 6.0, 0.4), (-300.0, 22.0, -0.3), (330.0, 14.0, -0.5), (372.0, 0.0, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
    grains.append(Grain(c: CGPoint(x: heapCX + dx, y: heapBase - 10 + dy), w: 54, h: 24, angle: a, tone: 0.5))
}
grains.sort { $0.c.y < $1.c.y }   // back (higher) first, front (lower) last

for g in grains {
    ctx.saveGState()
    ctx.translateBy(x: g.c.x, y: g.c.y); ctx.rotate(by: g.angle)
    let rect = CGRect(x: -g.w / 2, y: -g.h / 2, width: g.w, height: g.h)
    // shadow cast onto the grains behind
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 8, color: rgb(0x000000, 0.55))
    ctx.setFillColor(rgb(goldDark)); ctx.fillEllipse(in: rect)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: rect); ctx.clip()
    let base: UInt32 = g.tone < 0.25 ? 0xD4A911 : (g.tone > 0.8 ? 0xEBC32A : gold)
    ctx.drawRadialGradient(gradient([(goldLight, 0), (base, 0.45), (goldDark, 1)]),
                           startCenter: CGPoint(x: -g.w * 0.10, y: -g.h * 0.18), startRadius: 0,
                           endCenter: CGPoint(x: 0, y: g.h * 0.10), endRadius: g.w * 0.50, options: [.drawsAfterEndLocation])
    // specular streak along the grain
    ctx.setFillColor(rgb(0xFFF8D8, 0.42))
    ctx.fillEllipse(in: CGRect(x: -g.w * 0.30, y: -g.h * 0.30, width: g.w * 0.52, height: g.h * 0.16))
    ctx.restoreGState()
    ctx.addEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75)); ctx.setStrokeColor(rgb(goldDeep, 0.45)); ctx.setLineWidth(1.5); ctx.strokePath()
    ctx.restoreGState()
}

// Soft top-light sheen over the tile.
ctx.drawLinearGradient(gradient([(0xFFFFFF, 0), (0xFFFFFF, 1)], alpha: [0.06, 0]), start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.midY), options: [])
ctx.restoreGState()

// Rim: dark outer edge plus a hairline inner highlight.
ctx.addPath(tilePath); ctx.setStrokeColor(rgb(0x000000, 0.5)); ctx.setLineWidth(3); ctx.strokePath()
ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2.5, dy: 2.5), cornerWidth: 820 * 0.2237, cornerHeight: 820 * 0.2237, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(2); ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
