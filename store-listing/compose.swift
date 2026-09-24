import AppKit

// Usage: swift compose.swift <rawDir> <outDir> <iconPath>
let args = CommandLine.arguments
let rawDir = args[1], outDir = args[2], iconPath = args[3]

let purpleDark = NSColor(red: 0.30, green: 0.17, blue: 0.62, alpha: 1)
let purple = NSColor(red: 0.412, green: 0.255, blue: 0.776, alpha: 1)
let purpleLight = NSColor(red: 0.62, green: 0.40, blue: 0.95, alpha: 1)

func savePNG(_ image: NSImage, size: NSSize, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

func render(size: NSSize, _ draw: (CGContext) -> Void) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
}

func gradient(_ ctx: CGContext, rect: CGRect, colors: [NSColor], start: CGPoint, end: CGPoint) {
    let cg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray, locations: nil)!
    ctx.drawLinearGradient(cg, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func drawText(_ text: String, font: NSFont, color: NSColor, in rect: CGRect, align: NSTextAlignment = .center) {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.boundingRect(with: NSSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    // Vertically top-align inside rect (flipped coordinates not used; y grows upward).
    let drawRect = NSRect(x: rect.minX, y: rect.maxY - bounds.height, width: rect.width, height: bounds.height)
    s.draw(with: drawRect, options: [.usesLineFragmentOrigin])
}

/// Draws `image` into `rect` clipped to a rounded rect with a soft shadow.
func drawPhone(_ ctx: CGContext, image: NSImage, rect: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.restoreGState()
    // Thin bezel highlight
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.setLineWidth(6)
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: radius - 3, cornerHeight: radius - 3, transform: nil))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Store screenshots (1080 x 1920, caption above the phone)

let shots: [(file: String, title: String, subtitle: String)] = [
    ("home",    "Track every book you read",     "Your current reads, progress and daily goal in one place"),
    ("session", "Time your reading sessions",    "Start the timer, read, and log pages when you finish"),
    ("goals",   "Set goals and keep your streak", "Daily minutes and yearly targets that update themselves"),
    ("library", "Your whole library, organized", "Reading, want to read and finished, with beautiful covers"),
    ("stats",   "See your reading habits",       "Weekly minutes, pages and genres in clear charts"),
    ("journal", "Remember what moved you",       "Write a note after each session and keep it forever"),
]

let W: CGFloat = 1080, H: CGFloat = 1920
for (index, shot) in shots.enumerated() {
    guard let raw = NSImage(contentsOfFile: "\(rawDir)/\(shot.file).png") else { print("missing \(shot.file)"); continue }
    let img = render(size: NSSize(width: W, height: H)) { ctx in
        gradient(ctx, rect: CGRect(x: 0, y: 0, width: W, height: H), colors: [purpleLight, purple, purpleDark],
                 start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0))
        // Soft glow behind the phone
        ctx.saveGState()
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W/2, y: 700), startRadius: 0, endCenter: CGPoint(x: W/2, y: 700), endRadius: 900, options: [])
        ctx.restoreGState()

        // Caption block (top)
        drawText(shot.title, font: NSFont.systemFont(ofSize: 78, weight: .bold), color: .white,
                 in: CGRect(x: 80, y: H - 300, width: W - 160, height: 210))
        drawText(shot.subtitle, font: NSFont.systemFont(ofSize: 36, weight: .medium), color: NSColor.white.withAlphaComponent(0.85),
                 in: CGRect(x: 120, y: H - 440, width: W - 240, height: 120))

        // Phone (raw screenshot aspect), bottom edge runs off the canvas
        let aspect = raw.size.height / raw.size.width
        let phoneW: CGFloat = 860
        let phoneH = phoneW * aspect
        let rect = CGRect(x: (W - phoneW) / 2, y: H - 470 - phoneH, width: phoneW, height: phoneH)
        drawPhone(ctx, image: raw, rect: rect, radius: 100)
    }
    savePNG(img, size: NSSize(width: W, height: H), to: "\(outDir)/screenshots/\(index + 1)-\(shot.file).png")
    print("wrote \(index + 1)-\(shot.file).png")
}

// MARK: - Feature graphic (1024 x 500)

let FW: CGFloat = 1024, FH: CGFloat = 500
let icon = NSImage(contentsOfFile: iconPath)!
let heroRaw = NSImage(contentsOfFile: "\(rawDir)/home.png")
let feature = render(size: NSSize(width: FW, height: FH)) { ctx in
    gradient(ctx, rect: CGRect(x: 0, y: 0, width: FW, height: FH), colors: [purpleLight, purple, purpleDark],
             start: CGPoint(x: 0, y: FH), end: CGPoint(x: FW, y: 0))
    ctx.saveGState()
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor.white.withAlphaComponent(0.2).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 800, y: 150), startRadius: 0, endCenter: CGPoint(x: 800, y: 150), endRadius: 520, options: [])
    ctx.restoreGState()

    // App icon with rounded corners + shadow
    let iconRect = CGRect(x: 70, y: FH - 70 - 150, width: 150, height: 150)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 34, cornerHeight: 34, transform: nil)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 34, cornerHeight: 34, transform: nil)); ctx.clip()
    icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.restoreGState()

    drawText("ReadTime", font: NSFont.systemFont(ofSize: 76, weight: .bold), color: .white,
             in: CGRect(x: 250, y: FH - 70 - 95, width: 500, height: 95), align: .left)
    drawText("Read more. Track everything.", font: NSFont.systemFont(ofSize: 30, weight: .medium), color: NSColor.white.withAlphaComponent(0.9),
             in: CGRect(x: 254, y: FH - 175 - 45, width: 500, height: 45), align: .left)
    drawText("Books · Goals · Timer · Stats · Journal", font: NSFont.systemFont(ofSize: 24, weight: .regular), color: NSColor.white.withAlphaComponent(0.7),
             in: CGRect(x: 72, y: 60, width: 560, height: 40), align: .left)

    // Phone on the right, running off the bottom edge
    if let heroRaw {
        let aspect = heroRaw.size.height / heroRaw.size.width
        let phoneW: CGFloat = 300
        let phoneH = phoneW * aspect
        let rect = CGRect(x: FW - phoneW - 80, y: FH - 60 - phoneH, width: phoneW, height: phoneH)
        drawPhone(ctx, image: heroRaw, rect: rect, radius: 40)
    }
}
savePNG(feature, size: NSSize(width: FW, height: FH), to: "\(outDir)/feature-graphic.png")
print("wrote feature-graphic.png")
