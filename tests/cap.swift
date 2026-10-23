import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit
let dur = Double(CommandLine.arguments[1])!, out = CommandLine.arguments[2]
let sem = DispatchSemaphore(value: 0)
Task {
  let content = try await SCShareableContent.current
  let d = content.displays[0]
  let f = SCContentFilter(display: d, excludingWindows: [])
  let c = SCStreamConfiguration(); c.width = 720; c.height = 450; c.showsCursor = false
  var frames: [(Double, CGImage)] = []
  let t0 = Date()
  while Date().timeIntervalSince(t0) < dur {
    if let im = try? await SCScreenshotManager.captureImage(contentFilter: f, configuration: c) { frames.append((Date().timeIntervalSince(t0), im)) }
  }
  for (i,(t,im)) in frames.enumerated() {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: String(format:"%@/c%03d_%.2f.jpg", out, i, t)) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, im, nil); CGImageDestinationFinalize(dst)
  }
  print(frames.count); sem.signal()
}
sem.wait()
