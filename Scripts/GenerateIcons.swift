#!/usr/bin/env swift

import AppKit
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw Failure(description: message)
}

func bitmap(from image: NSImage, size: Int) throws -> NSBitmapImageRep {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        try fail("GenerateIcons failed: could not allocate \(size)x\(size) bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func pngData(from rep: NSBitmapImageRep) throws -> Data {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        try fail("GenerateIcons failed: could not encode PNG")
    }
    return data
}

func loadSVG(_ path: String) throws -> NSImage {
    guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else {
        try fail("GenerateIcons failed: could not load SVG: \(path)")
    }
    return image
}

func trimTransparentPixels(_ rep: NSBitmapImageRep) throws -> NSBitmapImageRep {
    var minX = rep.pixelsWide
    var minY = rep.pixelsHigh
    var maxX = -1
    var maxY = -1

    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.01 else {
                continue
            }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else { return rep }
    let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    guard let cropped = rep.cgImage?.cropping(to: cropRect) else {
        try fail("GenerateIcons failed: could not crop transparent pixels")
    }
    return NSBitmapImageRep(cgImage: cropped)
}

func resize(_ source: NSBitmapImageRep, size: Int) throws -> NSBitmapImageRep {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        try fail("GenerateIcons failed: could not allocate resized \(size)x\(size) bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    context?.imageInterpolation = .high
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    NSImage(cgImage: source.cgImage!, size: NSSize(width: source.pixelsWide, height: source.pixelsHigh)).draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    try pngData(from: rep).write(to: URL(fileURLWithPath: path), options: .atomic)
}

do {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
    let design = "\(root)/Design"
    let assets = "\(root)/Sources/App/Assets.xcassets"
    let appIcon = "\(assets)/AppIcon.appiconset"
    let aboutHero = "\(assets)/AboutHeroIcon.imageset"

    let small = "\(design)/fancurve-tier1-favicon.svg"
    let menubar = "\(design)/fancurve-tier2-menubar.svg"
    let dock = "\(design)/fancurve-tier3-dock.svg"
    let full = "\(design)/fancurve-tier4-full.svg"

    for file in [small, menubar, dock, full] where !FileManager.default.fileExists(atPath: file) {
        try fail("missing icon source: \(file)")
    }

    try FileManager.default.createDirectory(atPath: appIcon, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: aboutHero, withIntermediateDirectories: true)

    let aboutHeroContents = """
    {
      "images" : [
        {
          "filename" : "AboutHeroIcon.png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "AboutHeroIcon@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "filename" : "AboutHeroIcon@3x.png",
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try aboutHeroContents.write(
        to: URL(fileURLWithPath: "\(aboutHero)/Contents.json"),
        atomically: true,
        encoding: .utf8
    )

    let smallMaster = try trimTransparentPixels(bitmap(from: loadSVG(small), size: 1024))
    let menubarMaster = try trimTransparentPixels(bitmap(from: loadSVG(menubar), size: 1024))
    let dockMaster = try trimTransparentPixels(bitmap(from: loadSVG(dock), size: 1024))
    let fullMaster = try trimTransparentPixels(bitmap(from: loadSVG(full), size: 1024))
    let aboutMaster = try bitmap(from: loadSVG(full), size: 1024)

    try writePNG(try resize(aboutMaster, size: 256), to: "\(aboutHero)/AboutHeroIcon.png")
    try writePNG(try resize(aboutMaster, size: 512), to: "\(aboutHero)/AboutHeroIcon@2x.png")
    try writePNG(try resize(aboutMaster, size: 768), to: "\(aboutHero)/AboutHeroIcon@3x.png")

    try writePNG(try resize(smallMaster, size: 16), to: "\(appIcon)/AppIcon-16.png")
    try writePNG(try resize(smallMaster, size: 32), to: "\(appIcon)/AppIcon-16@2x.png")
    try writePNG(try resize(menubarMaster, size: 32), to: "\(appIcon)/AppIcon-32.png")
    try writePNG(try resize(menubarMaster, size: 64), to: "\(appIcon)/AppIcon-32@2x.png")
    try writePNG(try resize(dockMaster, size: 128), to: "\(appIcon)/AppIcon-128.png")
    try writePNG(try resize(dockMaster, size: 256), to: "\(appIcon)/AppIcon-128@2x.png")
    try writePNG(try resize(dockMaster, size: 256), to: "\(appIcon)/AppIcon-256.png")
    try writePNG(try resize(dockMaster, size: 512), to: "\(appIcon)/AppIcon-256@2x.png")
    try writePNG(try resize(fullMaster, size: 512), to: "\(appIcon)/AppIcon-512.png")
    try writePNG(try resize(fullMaster, size: 1024), to: "\(appIcon)/AppIcon-512@2x.png")

    print("generated app icons from canonical tier1/2/3/4 SVGs")
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.description + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("GenerateIcons failed: \(error)\n").utf8))
    exit(1)
}
