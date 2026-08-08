#!/usr/bin/env swift
//
// Generates the app icon at every size the asset catalog needs, plus the
// 256 px copy used by the landing page.
//
//   swift Scripts/make-icon.swift
//
// The mark is the dashboard's own gauge ring, filled with water: it says
// "pool" and "monitoring" at once, and survives being shrunk to 16 px
// because it is two shapes, not a scene.
//
import AppKit

// MARK: - Geometry

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// App palette, same values as `Color.pool*` in the SwiftUI layer.
let deep = color(0x072A45)
let mid = color(0x0E5F8C)
let aqua = color(0x1AA0B4)
let foam = color(0xA8F0E9)

func drawIcon(in ctx: CGContext, side: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()

    // macOS icons sit inside their canvas with a margin; 824/1024 is the
    // proportion Apple's own icons use.
    let inset = side * 0.098
    let box = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = box.width * 0.2237  // Apple's squircle corner ratio.
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow, as macOS app icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.012),
                  blur: side * 0.03,
                  color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(deep)
    ctx.fillPath()
    ctx.restoreGState()

    // Body gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    if let gradient = CGGradient(colorsSpace: space, colors: [deep, mid, aqua] as CFArray,
                                 locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: box.minX, y: box.maxY),
            end: CGPoint(x: box.maxX, y: box.minY),
            options: []
        )
    }

    // Light falling from the top — a gradient, so it has no visible edge.
    if let sheen = CGGradient(colorsSpace: space,
                              colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray,
                              locations: [0, 1]) {
        ctx.drawLinearGradient(
            sheen,
            start: CGPoint(x: box.midX, y: box.maxY),
            end: CGPoint(x: box.midX, y: box.midY - box.height * 0.1),
            options: []
        )
    }
    ctx.restoreGState()

    // MARK: Gauge ring

    let center = CGPoint(x: box.midX, y: box.midY)
    let ringRadius = box.width * 0.295
    let ringWidth = box.width * 0.085

    // The 270° arc of the dashboard gauges: bottom-left to bottom-right.
    let start = CGFloat.pi * 0.75
    let end = CGFloat.pi * 2.25

    ctx.setLineCap(.round)
    ctx.setLineWidth(ringWidth)

    ctx.setStrokeColor(color(0xFFFFFF, 0.22))
    ctx.addArc(center: center, radius: ringRadius, startAngle: -start, endAngle: -end,
               clockwise: true)
    ctx.strokePath()

    // Filled portion — deliberately ~78 %, so the ring reads as a gauge
    // rather than a plain circle.
    ctx.setStrokeColor(color(0xFFFFFF, 0.95))
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: -start, endAngle: -(start + (end - start) * 0.78),
               clockwise: true)
    ctx.strokePath()

    // MARK: Water inside the ring

    let innerRadius = ringRadius - ringWidth * 0.95

    // Darken the disc first so the pale water reads against the body
    // gradient wherever the two get close in value.
    ctx.setFillColor(color(0x062033, 0.45))
    ctx.fillEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                               width: innerRadius * 2, height: innerRadius * 2))

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                              width: innerRadius * 2, height: innerRadius * 2))
    ctx.clip()

    func wave(level: CGFloat, amplitude: CGFloat, phase: CGFloat, fill: CGColor) {
        let path = CGMutablePath()
        let left = center.x - innerRadius
        let right = center.x + innerRadius
        let baseline = center.y - innerRadius + innerRadius * 2 * level
        path.move(to: CGPoint(x: left, y: center.y - innerRadius))
        path.addLine(to: CGPoint(x: left, y: baseline))
        var x = left
        while x <= right {
            let t = (x - left) / (right - left)
            let y = baseline + sin(t * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += max(1, side / 256)
        }
        path.addLine(to: CGPoint(x: right, y: center.y - innerRadius))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    wave(level: 0.62, amplitude: innerRadius * 0.075, phase: 0.6, fill: color(0x2AC1B8, 0.75))
    wave(level: 0.52, amplitude: innerRadius * 0.085, phase: 2.4, fill: foam)
    ctx.restoreGState()
}

// MARK: - Rendering

func render(px: Int) -> Data? {
    let side = CGFloat(px)
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    drawIcon(in: ctx, side: side)

    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

let root = FileManager.default.currentDirectoryPath
let iconset = "\(root)/HaywardMonitor/Assets.xcassets/AppIcon.appiconset"

for (name, px) in sizes {
    guard let data = render(px: px) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    let path = "\(iconset)/\(name).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(name).png (\(px)px)")
}

// Landing page copy.
if let data = render(px: 256) {
    try! data.write(to: URL(fileURLWithPath: "\(root)/docs/assets/icon-256.png"))
    print("wrote docs/assets/icon-256.png")
}
