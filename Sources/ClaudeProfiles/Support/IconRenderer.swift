import AppKit

enum IconRenderer {
    static let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, pixels) in sizes {
            guard let png = render(CGFloat(pixels)).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    static func render(_ size: CGFloat) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        // macOS icon grid: an 824/1024 body with a ~22% corner radius.
        let inset = size * 100 / 1024
        let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
        NSGradient(
            starting: NSColor(red: 0.93, green: 0.56, blue: 0.40, alpha: 1),
            ending: NSColor(red: 0.62, green: 0.29, blue: 0.62, alpha: 1))?.draw(in: shape, angle: -70)

        let people = NSImage.SymbolConfiguration(pointSize: size * 0.30, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(people)
        {
            let s = image.size
            image.draw(in: NSRect(x: (size - s.width) / 2, y: size * 0.47, width: s.width, height: s.height))
        }
        let arrows = NSImage.SymbolConfiguration(pointSize: size * 0.17, weight: .bold)
            .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.9)]))
        if let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(arrows)
        {
            let s = image.size
            image.draw(in: NSRect(x: (size - s.width) / 2, y: size * 0.24, width: s.width, height: s.height))
        }
        return rep
    }
}
