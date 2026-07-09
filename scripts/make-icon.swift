// Renders the StretchWatch app icon (1024²) — the signature breathing arc in an
// ember→coral gradient on warm ink, with a soft glow. Run: swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF)/255,
                                         CGFloat((hex >> 8) & 0xFF)/255,
                                         CGFloat(hex & 0xFF)/255, 1])!
}
let ink = rgb(0x0E0B12), ember = rgb(0xF2A65A), ember2 = rgb(0xE9683E)
let c = CGFloat(size) / 2

// Background
ctx.setFillColor(ink)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Soft ember glow behind the arc
if let glow = CGGradient(colorsSpace: cs, colors: [
    rgb(0xF2A65A), ink] as CFArray, locations: [0, 1]) {
    ctx.saveGState()
    ctx.setAlpha(0.28)
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: c, y: c), startRadius: 0,
                           endCenter: CGPoint(x: c, y: c), endRadius: c * 0.95, options: [])
    ctx.restoreGState()
}

// Breathing arc: a thick ring with a gap at the bottom, gradient stroke faked by
// drawing coral under, ember over with a partial sweep.
let radius = c * 0.52
let lineW = c * 0.20
ctx.setLineCap(.round)

func arc(_ start: CGFloat, _ end: CGFloat, _ color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineW)
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: c, y: c), radius: radius,
               startAngle: start, endAngle: end, clockwise: false)
    ctx.strokePath()
}
// full ring in coral, then ember over ~70% for a two-tone gradient feel
let gapStart = CGFloat.pi * 0.72   // gap centered at bottom
let gapEnd = CGFloat.pi * 0.28
arc(gapEnd, gapStart + CGFloat.pi * 2, ember2)
arc(gapEnd, gapEnd + CGFloat.pi * 1.15, ember)

// Movement dot on the ring (top-right), the thing you mirror
let dotAngle = CGFloat.pi * 0.18
let dot = CGPoint(x: c + cos(dotAngle) * radius, y: c + sin(dotAngle) * radius)
ctx.setFillColor(rgb(0xF3EEF6))
ctx.fillEllipse(in: CGRect(x: dot.x - lineW*0.34, y: dot.y - lineW*0.34,
                           width: lineW*0.68, height: lineW*0.68))

guard let image = ctx.makeImage() else { fatalError("no image") }
let outURL = URL(fileURLWithPath: "scripts/icon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.path)")
