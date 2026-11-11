#!/usr/bin/env swift
// Renders Vellforge.icns from code, so the icon is reproducible and versioned
// rather than a binary blob nobody can edit.
//
//   swift Scripts/make-icon.swift
//
// Design: the Vellforge mark from vellforge.com (one brass pane, two stacked
// beside it) on the site's warm charcoal, lit from the top.

import AppKit
import CoreGraphics
import Foundation

let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources")
let iconset = outputDir.appendingPathComponent("Vellforge.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue:  CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

/// Apple's icon grid: the squircle occupies the middle ~80% of the canvas.
func draw(size: CGFloat) -> CGImage? {
    let scale = size / 1024
    guard let context = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    context.scaleBy(x: scale, y: scale)

    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185,
                          transform: nil)

    // Ground: the site's warm charcoal, lighter at the top like a lit surface.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [hex(0x34302C), hex(0x141312)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: plate.maxY),
                               end: CGPoint(x: 0, y: plate.minY),
                               options: [])
    context.restoreGState()

    // Inner highlight, so the plate reads as a physical surface.
    context.saveGState()
    context.addPath(CGPath(roundedRect: plate.insetBy(dx: 6, dy: 6),
                           cornerWidth: 180, cornerHeight: 180, transform: nil))
    context.setStrokeColor(hex(0xFFFFFF, 0.10))
    context.setLineWidth(6)
    context.strokePath()
    context.restoreGState()

    // The panes, as in the vellforge.com mark.
    let field = plate.insetBy(dx: 168, dy: 168)
    let gap: CGFloat = 26
    let halfWidth = (field.width - gap) / 2
    let stackHeight = (field.height - gap) / 2

    func pane(_ rect: CGRect, fill: CGColor, radius: CGFloat = 26) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
                               cornerHeight: radius, transform: nil))
        context.setFillColor(fill)
        context.fillPath()
    }

    // Main pane, in brass.
    pane(CGRect(x: field.minX, y: field.minY, width: halfWidth, height: field.height),
         fill: hex(0xE0B25C))

    // Stacked panes, quieter.
    pane(CGRect(x: field.minX + halfWidth + gap, y: field.minY + stackHeight + gap,
                width: halfWidth, height: stackHeight),
         fill: hex(0xF3EFE9, 0.88))
    pane(CGRect(x: field.minX + halfWidth + gap, y: field.minY,
                width: halfWidth, height: stackHeight),
         fill: hex(0xF3EFE9, 0.50))

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// The exact set `iconutil` expects.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let image = draw(size: variant.size) else {
        print("failed at \(variant.name)"); exit(1)
    }
    write(image, to: iconset.appendingPathComponent("\(variant.name).png"))
}

// A standalone preview for the landing page and README.
if let big = draw(size: 1024) {
    write(big, to: outputDir.appendingPathComponent("icon-preview.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path,
                  "-o", outputDir.appendingPathComponent("Vellforge.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0
      ? "wrote Resources/Vellforge.icns"
      : "iconutil failed (\(task.terminationStatus))")
