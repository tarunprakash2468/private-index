#!/usr/bin/env swift
import AppKit
import Foundation

// -----------------------------------------------------------------------------
// generate_app_icons.swift
// Extracts, composes, and bundles custom app icons for macOS and iOS from source.
// -----------------------------------------------------------------------------

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let sourcePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : repoRoot.appendingPathComponent("assets/raw/source_icons.png").path

guard fileManager.fileExists(atPath: sourcePath) else {
    print("Error: Source image not found at \(sourcePath)")
    exit(1)
}

guard let srcImage = NSImage(contentsOfFile: sourcePath),
      let cgImage = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error: Could not decode source image at \(sourcePath)")
    exit(1)
}

print("==> Loaded source image: \(cgImage.width)x\(cgImage.height)")

// Center coordinates in source image (1024x571)
let iconCenters: [(name: String, cx: Int, cy: Int)] = [
    ("light", 191, 273),
    ("dark", 512, 273),
    ("clear", 833, 273)
]
let sourceCropSize = 270

// Create output directories
let assetsDir = repoRoot.appendingPathComponent("assets")
let macResourcesDir = repoRoot.appendingPathComponent("Apps/macOS/Resources")
let iosAppIconDir = repoRoot.appendingPathComponent("Apps/iOS/Assets.xcassets/AppIcon.appiconset")

try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: macResourcesDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: iosAppIconDir, withIntermediateDirectories: true)

// Helper to save PNG
func savePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("Failed to encode PNG for \(url.path)")
        return
    }
    do {
        try data.write(to: url)
        print("  ✓ Saved: \(url.path)")
    } catch {
        print("  ✗ Error saving \(url.path): \(error)")
    }
}

// Helper to scale CGImage
func scaleImage(_ image: CGImage, to targetSize: CGSize, interpolation: CGInterpolationQuality = .high) -> CGImage? {
    let width = Int(targetSize.width)
    let height = Int(targetSize.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else { return nil }

    ctx.interpolationQuality = interpolation
    ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    return ctx.makeImage()
}

// -----------------------------------------------------------------------------
// 1. Extract 1024x1024 Master Images for Light, Dark, Clear
// -----------------------------------------------------------------------------
print("==> [1/4] Extracting master icons...")
var masterImages: [String: CGImage] = [:]

for item in iconCenters {
    let cropRect = CGRect(
        x: item.cx - sourceCropSize / 2,
        y: item.cy - sourceCropSize / 2,
        width: sourceCropSize,
        height: sourceCropSize
    )
    guard let cropped = cgImage.cropping(to: cropRect),
          let scaled = scaleImage(cropped, to: CGSize(width: 1024, height: 1024)) else {
        print("Failed to crop/scale icon: \(item.name)")
        continue
    }
    masterImages[item.name] = scaled
    savePNG(scaled, to: assetsDir.appendingPathComponent("icon-\(item.name).png"))
}

// Set default repository icon to Light
if let lightMaster = masterImages["light"] {
    savePNG(lightMaster, to: assetsDir.appendingPathComponent("icon.png"))
}

// -----------------------------------------------------------------------------
// 2. Generate macOS HIG Icon (824x824 squircle with shadow on 1024x1024 canvas)
// -----------------------------------------------------------------------------
print("==> [2/4] Composing macOS HIG AppIcon...")
func createMacOSAppIcon(from master: CGImage) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: 1024,
        height: 1024,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high

    // macOS HIG specifications: 824x824 squircle centered in 1024x1024, corner radius ~185
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -20),
        blur: 28,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    )
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle and draw image
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    ctx.draw(master, in: iconRect)
    ctx.restoreGState()

    return ctx.makeImage()
}

guard let lightMaster = masterImages["light"],
      let macOSMaster = createMacOSAppIcon(from: lightMaster) else {
    print("Error: Could not generate macOS master icon")
    exit(1)
}

// -----------------------------------------------------------------------------
// 3. Build macOS .iconset and compile to AppIcon.icns
// -----------------------------------------------------------------------------
print("==> [3/4] Building macOS AppIcon.icns...")
let iconsetURL = fileManager.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconsetURL)
try? fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

for item in iconSizes {
    let px = item.size * item.scale
    let filename = item.scale == 1 ? "icon_\(item.size)x\(item.size).png" : "icon_\(item.size)x\(item.size)@2x.png"
    if let scaled = scaleImage(macOSMaster, to: CGSize(width: px, height: px)) {
        savePNG(scaled, to: iconsetURL.appendingPathComponent(filename))
    }
}

let icnsDestURL = macResourcesDir.appendingPathComponent("AppIcon.icns")
let iconutilProcess = Process()
iconutilProcess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilProcess.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsDestURL.path]

do {
    try iconutilProcess.run()
    iconutilProcess.waitUntilExit()
    if iconutilProcess.terminationStatus == 0 {
        print("  ✓ Compiled: \(icnsDestURL.path)")
    } else {
        print("  ✗ iconutil failed with status \(iconutilProcess.terminationStatus)")
    }
} catch {
    print("  ✗ iconutil execution error: \(error)")
}
try? fileManager.removeItem(at: iconsetURL)

// -----------------------------------------------------------------------------
// 4. Build iOS AppIcon.appiconset (Universal + iOS 18 Appearances)
// -----------------------------------------------------------------------------
print("==> [4/4] Building iOS AppIcon.appiconset...")
if let light = masterImages["light"] {
    savePNG(light, to: iosAppIconDir.appendingPathComponent("AppIcon.png"))
}
if let dark = masterImages["dark"] {
    savePNG(dark, to: iosAppIconDir.appendingPathComponent("AppIcon-Dark.png"))
}
if let clear = masterImages["clear"] {
    savePNG(clear, to: iosAppIconDir.appendingPathComponent("AppIcon-Tinted.png"))
}

let contentsJSON = """
{
  "images": [
    {
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "filename": "AppIcon.png"
    },
    {
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "appearances": [
        {
          "appearance": "luminosity",
          "value": "dark"
        }
      ],
      "filename": "AppIcon-Dark.png"
    },
    {
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "appearances": [
        {
          "appearance": "luminosity",
          "value": "tinted"
        }
      ],
      "filename": "AppIcon-Tinted.png"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""

try? contentsJSON.write(
    to: iosAppIconDir.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
print("  ✓ Created: \(iosAppIconDir.appendingPathComponent("Contents.json").path)")

print("\n🎉 Custom App Icons generated and bundled successfully!")
