#!/usr/bin/env swift
//
// Frames the raw App Store tour captures for the store: each capture inside a device
// frame, on a dark background, under one short caption.
//
// A set can have a background image instead of the fallback gradient:
// `docs/app-store-assets/background/<kind>.png` (iphone-69 or ipad-13), drawn to fill the
// canvas, centred, and cropped to it. Without that file the set gets a gradient drawn from
// system orange, so a fresh clone frames with no image. The caption contrast check reads
// whatever was drawn under the text, so an image that is too light behind the caption fails
// the run.
//
// The committed background images are generated, not photographed. Both come from one
// headless ComfyUI run:
//
//   model    z_image_turbo_bf16.safetensors, text encoder qwen_3_4b.safetensors,
//            VAE ae.safetensors
//   sampler  res_multistep, scheduler simple, 8 steps, cfg 1, denoise 1
//   shift    3 (ModelSamplingAuraFlow), negative is the zeroed prompt
//   prompt   "dark charcoal studio backdrop, one soft out-of-focus saturated deep
//            amber-orange light glow from the lower left, fine grain, top third nearly
//            black, no text, no objects"
//   iphone-69  832x1808, seed 101
//   ipad-13    1152x1536, seed 303
//
//   swift scripts/frame-screenshots.swift iphone-69 <raw dir> <out dir>
//   swift scripts/frame-screenshots.swift ipad-13   <raw dir> <out dir>
//   swift scripts/frame-screenshots.swift --list    the published names, one per line
//
// `scripts/screenshots.sh` calls it after a tour, and `scripts/screenshots.sh --frame`
// calls it on the committed raw captures without a tour.
//
// The app UI inside a frame is the capture, scaled and nothing else. App Review guideline
// 2.3.3 requires that, so the background, the frame, the phone's Dynamic Island and the
// caption are the only things drawn here.
//
// CoreGraphics, CoreText and ImageIO only, so it runs on any Mac that builds the app.

import CoreGraphics
import CoreText
import Foundation
import ImageIO

// MARK: - What is published

/// The store order, and the caption for each capture. The filename sets the upload order,
/// so a published image is `NN-<stem>.png` with `NN` from its place here. A raw capture
/// that is not listed is not published. App Store Connect takes at most ten per size, and
/// `scripts/screenshots.sh` refuses a longer list.
///
/// The listing leads with server administration: the dashboard, then the surfaces only an
/// administration client has (Docker, VMs, shares), then the service hub and the media
/// screens. The tour also captures `search`, `downloads`, `radarr-queue` and `indexers`.
/// Those features still exist and the description still names them, but the listing does
/// not lead with them. The connect screen is not in the set, because an empty sign-in form
/// shows nothing the app does.
///
/// Keep each caption short and true: no superlatives and no claim the picture does not
/// back up.
let LISTING: [(stem: String, caption: String)] = [
  ("dashboard", "Your whole server at a glance"),
  ("docker", "Start, stop and update containers"),
  ("vms", "Control your virtual machines"),
  ("shares", "Check every user share"),
  ("services", "Your self-hosted apps in one place"),
  ("radarr-library", "Manage your movie library"),
  ("streams", "See who is watching"),
  ("requests", "Approve requests from your users"),
  ("music", "Manage your music library"),
  ("subtitles", "Track missing subtitles"),
]

// MARK: - Sizes

/// One device kind: the canvas App Store Connect takes, the capture that goes in it, and
/// the frame around it.
struct Kind {
  let canvas: CGSize
  /// The tour's capture size. A capture of any other size is the wrong device.
  let capture: CGSize
  /// The display's corner radius in capture pixels. Measured from the keyboard's lower
  /// corners, which iOS draws concentric with the display: about 180 on the 6.9" phone and
  /// 55 on the 13" iPad. Rounded up, because a clip smaller than the drawn corner leaves a
  /// sliver of the app's background between the keyboard and the frame.
  let screenRadius: CGFloat
  /// The Dynamic Island in capture pixels, or nil for a device without one. The simulator
  /// does not draw it, and the status bar leaves its place empty, so drawing it covers no
  /// app UI.
  let island: CGRect?
  /// The bezel's width in canvas pixels.
  let bezel: CGFloat
  let captionSize: CGFloat
  /// Above the caption, between the caption and the device, and below the device.
  let top: CGFloat
  let gap: CGFloat
  let bottom: CGFloat
}

let kinds: [String: Kind] = [
  "iphone-69": Kind(
    canvas: CGSize(width: 1320, height: 2868), capture: CGSize(width: 1320, height: 2868),
    screenRadius: 186,
    // 126 by 37 points, 11 points from the top edge, at 3x.
    island: CGRect(x: 471, y: 34, width: 378, height: 112),
    bezel: 28, captionSize: 112, top: 170, gap: 120, bottom: 120),
  "ipad-13": Kind(
    canvas: CGSize(width: 2064, height: 2752), capture: CGSize(width: 2064, height: 2752),
    screenRadius: 60, island: nil, bezel: 40, captionSize: 132, top: 160, gap: 120,
    bottom: 130),
]

/// The most lines a caption may take. Every caption gets this much room, so the devices
/// sit at the same height across a set.
let captionLines = 2

// MARK: - Colour

/// iOS `systemOrange` in light appearance. Unraid's own colour is an orange, and the
/// background images use a warm orange light, so the fallback gradient uses it too.
let accent = RGB(hex: 0xFF9500)

struct RGB {
  var r, g, b: Double

  init(r: Double, g: Double, b: Double) { (self.r, self.g, self.b) = (r, g, b) }
  init(hex: Int) {
    self.init(
      r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255,
      b: Double(hex & 0xFF) / 255)
  }

  /// WCAG relative luminance.
  var luminance: Double {
    func linear(_ c: Double) -> Double {
      c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
  }

  func contrast(with other: RGB) -> Double {
    let (a, b) = (luminance, other.luminance)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  func cg(alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
  }
}

let white = RGB(r: 1, g: 1, b: 1)
/// The fallback gradient's charcoal, the same look as the background images: near black at
/// the top, where the caption sits, and a little lighter toward the bottom.
let backgroundTop = RGB(hex: 0x141416)
let backgroundBottom = RGB(hex: 0x222224)

// MARK: - Drawing

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// An opaque RGB canvas. `noneSkipLast` has no alpha, so the PNG has none either, which
/// App Store Connect requires.
func canvas(_ size: CGSize) -> CGContext {
  guard
    let context = CGContext(
      data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
      bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { fail("cannot make a \(Int(size.width))x\(Int(size.height)) canvas") }
  context.interpolationQuality = .high
  context.setShouldAntialias(true)
  return context
}

/// A rectangle measured from the canvas's top edge. CoreGraphics measures from the bottom.
func fromTop(_ context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)
  -> CGRect
{
  CGRect(x: x, y: CGFloat(context.height) - y - height, width: width, height: height)
}

/// The repository, from this script's own path, because the directories it is handed can be
/// a staging directory outside the tree.
let repoRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()

/// Where a set's optional background image lives, relative to the repository.
func backgroundPath(_ kind: String) -> String { "docs/app-store-assets/background/\(kind).png" }

/// The set's background image, or `nil` when the file does not exist and the set gets the
/// gradient.
func backgroundImage(_ kind: String) -> CGImage? {
  let url = repoRoot.appendingPathComponent(backgroundPath(kind))
  guard FileManager.default.fileExists(atPath: url.path) else { return nil }
  return loadImage(url)
}

/// Draws `image` over the whole canvas at the smallest scale that covers it, centred, so
/// whatever does not fit is cut off evenly on both sides.
func drawBackground(_ context: CGContext, image: CGImage) {
  let size = CGSize(width: context.width, height: context.height)
  let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
  let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
  context.draw(
    image,
    in: CGRect(
      x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
      width: drawn.width, height: drawn.height))
}

/// Says which gradient `drawBackground(_:)` draws, and how white reads on its top colour.
func describeGradient() {
  print(
    String(
      format:
        "background #%02X%02X%02X to #%02X%02X%02X with an orange glow at the lower left, "
        + "white reads at %.2f:1 on the top colour",
      Int(backgroundTop.r * 255), Int(backgroundTop.g * 255), Int(backgroundTop.b * 255),
      Int(backgroundBottom.r * 255), Int(backgroundBottom.g * 255),
      Int(backgroundBottom.b * 255), backgroundTop.contrast(with: white)))
}

func drawBackground(_ context: CGContext) {
  let size = CGSize(width: context.width, height: context.height)
  let gradient = CGGradient(
    colorsSpace: sRGB, colors: [backgroundTop.cg(), backgroundBottom.cg()] as CFArray,
    locations: [0, 1])!
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
  // One soft orange light from the lower left, as in the background images. It fades out
  // well below the caption, and `drawText` measures what is under the text anyway.
  let glow = CGGradient(
    colorsSpace: sRGB,
    colors: [accent.cg(alpha: 0.6), accent.cg(alpha: 0.2), accent.cg(alpha: 0)] as CFArray,
    locations: [0, 0.45, 1])!
  let centre = CGPoint(x: 0, y: size.height * 0.22)
  context.drawRadialGradient(
    glow, startCenter: centre, startRadius: 0, endCenter: centre,
    endRadius: max(size.width, size.height) * 0.55, options: [])
}

func loadImage(_ url: URL) -> CGImage {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { fail("cannot read \(url.path)") }
  return image
}

/// Draws `capture` as a device's screen with its top-left corner at `origin` (from the
/// canvas's top), `scale` capture pixels to canvas pixels.
func drawDevice(
  _ context: CGContext, _ capture: CGImage, kind: Kind, origin: CGPoint, scale: CGFloat
) {
  let screenSize = CGSize(
    width: CGFloat(capture.width) * scale, height: CGFloat(capture.height) * scale)
  let screen = fromTop(
    context, x: origin.x + kind.bezel, y: origin.y + kind.bezel, width: screenSize.width,
    height: screenSize.height)
  let outer = screen.insetBy(dx: -kind.bezel, dy: -kind.bezel)
  let screenRadius = kind.screenRadius * scale
  let outerRadius = screenRadius + kind.bezel

  func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  // The shadow goes on the body only. It is cleared before the capture is drawn, or the
  // screen casts one of its own onto the bezel.
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: -outer.height * 0.018), blur: outer.height * 0.05,
    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
  context.addPath(rounded(outer, outerRadius))
  context.setFillColor(RGB(hex: 0x5C5C60).cg())
  context.fillPath()
  context.restoreGState()

  // A thin light edge, then the black bezel inside it.
  let rim = max(3, kind.bezel * 0.14)
  context.addPath(rounded(outer.insetBy(dx: rim, dy: rim), outerRadius - rim))
  context.setFillColor(RGB(hex: 0x0B0B0C).cg())
  context.fillPath()

  context.saveGState()
  context.addPath(rounded(screen, screenRadius))
  context.clip()
  context.draw(capture, in: screen)
  if let island = kind.island {
    let pill = CGRect(
      x: screen.minX + island.minX * scale, y: screen.maxY - island.maxY * scale,
      width: island.width * scale, height: island.height * scale)
    context.addPath(rounded(pill, pill.height / 2))
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fillPath()
  }
  context.restoreGState()
}

/// The lightest colour already drawn inside `rect`, sampled every few pixels.
func lightest(_ context: CGContext, in rect: CGRect) -> RGB {
  let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
  // Row 0 of the buffer is the canvas's top edge.
  let top = context.height - Int(rect.maxY)
  var best = RGB(r: 0, g: 0, b: 0)
  for row in stride(from: max(0, top), to: min(context.height, top + Int(rect.height)), by: 4) {
    for column in stride(
      from: max(0, Int(rect.minX)), to: min(context.width, Int(rect.maxX)), by: 4)
    {
      let pixel = pixels + row * context.bytesPerRow + column * 4
      let colour = RGB(
        r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
      if colour.luminance > best.luminance { best = colour }
    }
  }
  return best
}

/// Draws `text` centred in `box` (from the canvas's top), in the bold system font, which is
/// SF Pro. Fails when it needs more than `maxLines`, rather than shrink one caption and not
/// the others. Fails when white reads below 4.5:1 on the lightest pixel under the box.
func drawText(_ context: CGContext, _ text: String, size: CGFloat, box: CGRect, maxLines: Int) {
  let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)!
  let lineHeight = size * 1.12
  var alignment = CTTextAlignment.center
  let style = withUnsafeBytes(of: &alignment) { align in
    withUnsafeBytes(of: lineHeight) { height in
      let settings = [
        CTParagraphStyleSetting(
          spec: .alignment, valueSize: align.count, value: align.baseAddress!),
        CTParagraphStyleSetting(
          spec: .minimumLineHeight, valueSize: height.count, value: height.baseAddress!),
        CTParagraphStyleSetting(
          spec: .maximumLineHeight, valueSize: height.count, value: height.baseAddress!),
      ]
      return CTParagraphStyleCreate(settings, settings.count)
    }
  }
  let string = NSAttributedString(
    string: text,
    attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): white.cg(),
      NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
    ])
  let setter = CTFramesetterCreateWithAttributedString(string)
  let target = fromTop(context, x: box.minX, y: box.minY, width: box.width, height: box.height)
  // Read from what is drawn under the text, not from the gradient's end colours, so the
  // glow and the background image are counted.
  let contrast = lightest(context, in: target).contrast(with: white)
  guard contrast >= 4.5 else {
    fail(String(format: "'%@' reads at %.2f:1 on its background", text, contrast))
  }
  print(String(format: "  the text reads at %.2f:1 or better on its background", contrast))
  func lineCount(_ width: CGFloat) -> Int {
    let tall = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), tall, nil)
    return (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
  }
  let lines = lineCount(target.width)
  guard lines >= 1, lines <= maxLines else {
    fail("'\(text)' takes \(lines) lines at \(Int(size)) pt, and the most is \(maxLines)")
  }
  // Wrapped text is set in the narrowest width that keeps the same number of lines, so the
  // lines come out even and no one word sits alone on the last.
  var narrow = target.width / CGFloat(lines)
  var wide = target.width
  while wide - narrow > 1 {
    let midpoint = (narrow + wide) / 2
    if lineCount(midpoint) > lines { narrow = midpoint } else { wide = midpoint }
  }
  let width = lines > 1 ? ceil(wide) : target.width
  let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
    setter, CFRange(location: 0, length: 0), nil,
    CGSize(width: width, height: .greatestFiniteMagnitude), nil)
  // Centred in the box both ways.
  let path = CGPath(
    rect: CGRect(
      x: target.minX + (target.width - width) / 2,
      y: target.minY + (target.height - fitted.height) / 2,
      width: width, height: ceil(fitted.height)), transform: nil)
  let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
  let range = CTFrameGetVisibleStringRange(frame)
  guard range.length == (text as NSString).length else {
    fail("'\(text)' does not fit its box")
  }
  context.textMatrix = .identity
  CTFrameDraw(frame, context)
}

func writePNG(_ image: CGImage, to url: URL) {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, "public.png" as CFString, 1, nil)
  else { fail("cannot write \(url.path)") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

// MARK: - The job

func frameSet(_ name: String, kind: Kind, raw: URL, out: URL) {
  let listed = Set(LISTING.map(\.stem))
  let unlisted = ((try? FileManager.default.contentsOfDirectory(atPath: raw.path)) ?? [])
    .filter { $0.hasSuffix(".png") && !listed.contains(String($0.dropLast(4))) }
  for file in unlisted.sorted() { print("\(name): not published: \(file)") }

  let image = backgroundImage(name)
  if let image {
    print("\(name): background \(backgroundPath(name)), \(image.width)x\(image.height), filled")
  } else {
    describeGradient()
  }

  for (index, shot) in LISTING.enumerated() {
    let capture = loadImage(raw.appendingPathComponent("\(shot.stem).png"))
    guard CGFloat(capture.width) == kind.capture.width,
      CGFloat(capture.height) == kind.capture.height
    else {
      fail(
        "\(name)/\(shot.stem).png is \(capture.width)x\(capture.height), expected "
          + "\(Int(kind.capture.width))x\(Int(kind.capture.height))")
    }
    let context = canvas(kind.canvas)
    if let image {
      drawBackground(context, image: image)
    } else {
      drawBackground(context)
    }

    let width = kind.canvas.width
    let margin = width * 0.08
    let captionHeight = kind.captionSize * 1.12 * CGFloat(captionLines)
    drawText(
      context, shot.caption, size: kind.captionSize,
      box: CGRect(x: margin, y: kind.top, width: width - 2 * margin, height: captionHeight),
      maxLines: captionLines)

    let deviceTop = kind.top + captionHeight + kind.gap
    let deviceHeight = kind.canvas.height - deviceTop - kind.bottom
    let scale = (deviceHeight - 2 * kind.bezel) / kind.capture.height
    let deviceWidth = kind.capture.width * scale + 2 * kind.bezel
    drawDevice(
      context, capture, kind: kind,
      origin: CGPoint(x: (width - deviceWidth) / 2, y: deviceTop), scale: scale)

    let file = String(format: "%02d-%@.png", index + 1, shot.stem)
    writePNG(context.makeImage()!, to: out.appendingPathComponent(file))
    print("\(name): \(file) \"\(shot.caption)\"")
  }
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--list"] {
  for shot in LISTING { print(shot.stem) }
  exit(0)
}
guard arguments.count == 3 else {
  fail("usage: frame-screenshots.swift iphone-69|ipad-13 <raw dir> <out dir>, or --list")
}
let job = arguments[0]
guard let kind = kinds[job] else { fail("unknown kind '\(job)' (iphone-69|ipad-13)") }
let raw = URL(fileURLWithPath: arguments[1])
let out = URL(fileURLWithPath: arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
frameSet(job, kind: kind, raw: raw, out: out)
