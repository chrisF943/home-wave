// Builds AppIcon.icns from a source PNG.
//   swift scripts/make-icon.swift icon/AppIcon.png icon/AppIcon.icns
//
// The artwork is fitted (aspect preserved) into 82% of each square canvas,
// which is Apple's app-icon grid — filling edge to edge makes the icon read
// oversized next to other apps in the Dock.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <out.icns>\n".utf8))
    exit(1)
}
let sourceURL = URL(fileURLWithPath: args[1])
let icnsURL = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(sourceURL.path)\n".utf8))
    exit(1)
}

let iconsetURL = icnsURL.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// (pixel size, iconset filename) — every slot iconutil expects.
let slots: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

func render(size: Int, to url: URL) throws {
    let canvas = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    let box = canvas * 0.82
    let sw = CGFloat(artwork.width), sh = CGFloat(artwork.height)
    let scale = min(box / sw, box / sh)
    let w = sw * scale, h = sh * scale
    ctx.draw(artwork, in: CGRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h))

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

for (size, name) in slots {
    try render(size: size, to: iconsetURL.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

try FileManager.default.removeItem(at: iconsetURL)
print("wrote \(icnsURL.path)")
