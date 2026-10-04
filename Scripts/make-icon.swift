import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("Orbit.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor(calibratedRed: 0.045, green: 0.06, blue: 0.067, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: bounds.insetBy(dx: CGFloat(pixels) * 0.07, dy: CGFloat(pixels) * 0.07),
      xRadius: CGFloat(pixels) * 0.20, yRadius: CGFloat(pixels) * 0.20
    ).fill()
    let mint = NSColor(calibratedRed: 0.48, green: 0.91, blue: 0.72, alpha: 1)
    for fraction in [0.27, 0.40, 0.55] {
      let dimension = CGFloat(pixels) * fraction
      let orbit = NSBezierPath(
        ovalIn: NSRect(
          x: (CGFloat(pixels) - dimension) / 2, y: (CGFloat(pixels) - dimension) / 2,
          width: dimension, height: dimension))
      orbit.lineWidth = CGFloat(pixels) * 0.018
      mint.withAlphaComponent(fraction == 0.40 ? 1 : 0.25).setStroke()
      orbit.stroke()
    }
    mint.setFill()
    NSBezierPath(
      ovalIn: NSRect(
        x: CGFloat(pixels) * 0.64, y: CGFloat(pixels) * 0.58, width: CGFloat(pixels) * 0.07,
        height: CGFloat(pixels) * 0.07)
    ).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
  }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
  "-c", "icns", iconset.path, "-o", output.appendingPathComponent("Orbit.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: iconset)
