// Draws the README logo: the About pane's mark (SeamMark in SettingsWindow.swift) as an animated
// SVG. A → 아 → あ one after another in place, then all three cut into rows (the menu-bar icon's
// shape), and round again. Letters are glyph outlines, so the SVG needs no fonts.
//   logo-light.svg  dark tile, for GitHub's light theme
//   logo-dark.svg   light tile, for the dark theme
// Reduce Motion shows only the joined mark.
// usage: swift scripts/make-readme-logo.swift <output directory>
import AppKit
import CoreText

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let H: CGFloat = 160, W = H * 1.25

func roundedFont(_ size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
}

/// Outline of `text` centred in the tile, in SVG coordinates (y down), scaled by `grow`.
func glyphPath(_ text: String, size: CGFloat, grow: CGFloat = 1) -> CGPath {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: roundedFont(size)]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
        for i in 0..<count {
            if let g = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                path.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
    }
    let box = path.boundingBoxOfPath
    var move = CGAffineTransform(translationX: W / 2, y: H / 2)
        .scaledBy(x: grow, y: -grow)
        .translatedBy(x: -box.midX, y: -box.midY)
    return path.copy(using: &move)!
}

func svgData(_ path: CGPath) -> String {
    var d = ""
    func p(_ pt: CGPoint) -> String { String(format: "%.2f %.2f", pt.x, pt.y) }
    path.applyWithBlock { element in
        let e = element.pointee, pts = e.points
        switch e.type {
        case .moveToPoint: d += "M\(p(pts[0]))"
        case .addLineToPoint: d += "L\(p(pts[0]))"
        case .addQuadCurveToPoint: d += "Q\(p(pts[0])) \(p(pts[1]))"
        case .addCurveToPoint: d += "C\(p(pts[0])) \(p(pts[1])) \(p(pts[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

let letters: [(String, CGFloat)] = [("A", 0.64), ("아", 0.6), ("あ", 0.6)]

// Timing as in SeamMark: each letter holds 2.2 s, the joined mark 3.4 s, 1.2 s crossfades.
let fade = 1.2
let holds = [2.2, 2.2, 2.2, 3.4]
let cycle = holds.reduce(0, +) + fade * Double(holds.count)

/// Keyframes for stage `k`: fully in at `start`, out after its hold. Stage 0 is in at time 0 and
/// fades in again at the end of the cycle, under the joined mark's fade-out.
func keyframes(_ k: Int) -> String {
    let start = holds[..<k].reduce(0, +) + fade * Double(k)
    func pct(_ t: Double) -> String { String(format: "%.3f%%", t / cycle * 100) }
    let hidden = "opacity:0", ease = "animation-timing-function:cubic-bezier(.37,0,.63,1)"
    let shown = "opacity:1;transform:scale(1);filter:blur(0)"
    let inFrom = "opacity:0;transform:scale(1.06);filter:blur(2px)"
    let outTo = "opacity:0;transform:scale(.94);filter:blur(2px)"
    var frames: [String] = []
    if k == 0 {
        frames.append("0%{\(shown);\(ease)}")
    } else {
        frames.append("0%,\(pct(start - fade)){\(inFrom);\(ease)}")
        frames.append("\(pct(start)){\(shown)}")
    }
    let out = start + holds[k]
    frames.append("\(pct(out)){\(shown);\(ease)}")
    frames.append("\(pct(out + fade)){\(outTo)}")
    if k == 0 {
        frames.append("\(pct(out + fade + 0.001)),\(pct(cycle - fade)){\(inFrom);\(ease)}")
        frames.append("100%{\(shown)}")
    } else {
        frames.append("100%{\(hidden)}")
    }
    return "@keyframes s\(k){\(frames.joined())}"
}

func svg(tile: String, ink: String) -> String {
    var body: [String] = []
    for (i, (text, size)) in letters.enumerated() {
        body.append("<g class=\"s s\(i)\"><path d=\"\(svgData(glyphPath(text, size: H * size)))\"/></g>")
    }
    // Joined: each letter, grown, shows only in its own row of the band, with thin gaps.
    let band = H * 0.62, gap = H * 0.03, grow: CGFloat = 1.32
    let row = (band - gap * CGFloat(letters.count - 1)) / CGFloat(letters.count)
    var defs: [String] = [], joined: [String] = []
    for (i, (text, size)) in letters.enumerated() {
        let y = H / 2 - band / 2 + CGFloat(i) * (row + gap) + H * 0.01
        defs.append(String(format: "<clipPath id=\"r%d\"><rect x=\"0\" y=\"%.2f\" width=\"%.0f\" height=\"%.2f\"/></clipPath>", i, y, W, row))
        joined.append("<path clip-path=\"url(#r\(i))\" d=\"\(svgData(glyphPath(text, size: H * size, grow: grow)))\"/>")
    }
    body.append("<g class=\"s s3\">\(joined.joined())</g>")

    let css = """
    .s{transform-box:view-box;transform-origin:50% 50%;animation:\(String(format: "%.1f", cycle))s infinite both}
    \((0...3).map { ".s\($0){animation-name:s\($0)}" }.joined())
    \((0...3).map(keyframes).joined(separator: "\n"))
    @media (prefers-reduced-motion:reduce){.s{animation:none;opacity:0}.s3{opacity:1}}
    """
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(W)) \(Int(H))" width="\(Int(W))" height="\(Int(H))" role="img" aria-label="Seamtype">
    <style>
    \(css)
    </style>
    <defs>\(defs.joined())</defs>
    <rect width="\(Int(W))" height="\(Int(H))" rx="\(Int(H * 0.28))" fill="\(tile)"/>
    <g fill="\(ink)">
    \(body.joined(separator: "\n"))
    </g>
    </svg>

    """
}

try! svg(tile: "#1d1d1f", ink: "#ffffff").write(to: outDir.appendingPathComponent("logo-light.svg"), atomically: true, encoding: .utf8)
try! svg(tile: "#f5f5f7", ink: "#0d1117").write(to: outDir.appendingPathComponent("logo-dark.svg"), atomically: true, encoding: .utf8)
