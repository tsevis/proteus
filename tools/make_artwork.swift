// Renders Proteus's icon and splash art as tile mosaics in the Tsevis palette.
// Usage: swift tools/make_artwork.swift <output-dir>
import AppKit
import CoreText

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r / 255; self.g = g / 255; self.b = b / 255 }
    private init(unit r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }

    func mixed(_ other: RGB, _ t: CGFloat) -> RGB {
        RGB(unit: r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

enum Palette {
    static let turquoise = RGB(26, 175, 165)
    static let blue = RGB(55, 97, 160)
    static let white = RGB(255, 255, 255)
    static let deepInk = RGB(17, 34, 51)
}

/// Deterministic jitter, so every build draws the same mosaic.
struct Jitter {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
}

func bitmap(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, to url: URL, as type: NSBitmapImageRep.FileType) throws {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let props: [NSBitmapImageRep.PropertyKey: Any] = type == .jpeg ? [.compressionFactor: 0.9] : [:]
    try rep.representation(using: type, properties: props)!.write(to: url)
}

func glyphPath(_ text: String, size: CGFloat, centeredIn rect: CGRect) -> CGPath {
    let font = NSFont.systemFont(ofSize: size, weight: .black) as CTFont
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var points = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &points)
        for (glyph, point) in zip(glyphs, points) {
            if let p = CTFontCreatePathForGlyph(font, glyph, nil) {
                path.addPath(p, transform: CGAffineTransform(translationX: point.x, y: point.y))
            }
        }
    }
    let box = path.boundingBoxOfPath
    let move = CGAffineTransform(translationX: rect.midX - box.midX, y: rect.midY - box.midY)
    return path.copy(using: [move])!
}

/// Fills `area` with square tiles; `color` picks each tile's colour from its centre.
func drawMosaic(in ctx: CGContext, area: CGRect, tile: CGFloat, grout: CGFloat, seed: UInt64,
                color: (CGPoint, inout Jitter) -> RGB) {
    var jitter = Jitter(seed: seed)
    var y = area.minY
    while y < area.maxY {
        var x = area.minX
        while x < area.maxX {
            let centre = CGPoint(x: x + tile / 2, y: y + tile / 2)
            let shade = color(centre, &jitter)
            ctx.setFillColor(shade.cg())
            let inset = CGRect(x: x, y: y, width: tile, height: tile).insetBy(dx: grout / 2, dy: grout / 2)
            ctx.addPath(CGPath(roundedRect: inset, cornerWidth: grout, cornerHeight: grout, transform: nil))
            ctx.fillPath()
            x += tile
        }
        y += tile
    }
}

func renderIcon(size: Int) -> CGContext {
    let s = CGFloat(size)
    let ctx = bitmap(size, size)
    // macOS icon grid: an 824-pt squircle centred on a 1024-pt canvas.
    let body = CGRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let radius = body.width * 0.2237
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(Palette.deepInk.cg())
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let letter = glyphPath("P", size: body.height * 0.78, centeredIn: body)
    let tile = body.width / 27
    drawMosaic(in: ctx, area: body, tile: tile, grout: tile * 0.14, seed: 7) { p, j in
        let t = (p.x - body.minX) / body.width
        if letter.contains(p) {
            // The letter changes form from left to right: white turning turquoise.
            return Palette.white.mixed(Palette.turquoise, min(1, max(0, t * 1.3 - 0.15) + j.next() * 0.12))
        }
        let depth = (p.y - body.minY) / body.height
        return Palette.deepInk.mixed(Palette.blue, depth * 0.75 + j.next() * 0.2)
    }
    ctx.restoreGState()
    return ctx
}

func renderSplash(width: Int, height: Int) -> CGContext {
    let ctx = bitmap(width, height)
    let area = CGRect(x: 0, y: 0, width: width, height: height)
    ctx.setFillColor(Palette.deepInk.cg())
    ctx.fill(area)
    let word = glyphPath("Aa → Bb", size: CGFloat(height) * 0.40,
                         centeredIn: area.offsetBy(dx: CGFloat(width) * 0.12, dy: CGFloat(height) * 0.16))
    let tile = CGFloat(height) / 30
    drawMosaic(in: ctx, area: area, tile: tile, grout: tile * 0.14, seed: 11) { p, j in
        let t = p.x / area.width
        if word.contains(p) {
            return Palette.white.mixed(Palette.turquoise, t * 0.9 + j.next() * 0.1)
        }
        return Palette.deepInk.mixed(Palette.blue, t * 0.7 + j.next() * 0.25)
    }
    return ctx
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try save(renderIcon(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"), as: .png)
    try save(renderIcon(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"), as: .png)
}
try save(renderSplash(width: 1280, height: 440), to: out.appendingPathComponent("SplashArt.jpg"), as: .jpeg)
