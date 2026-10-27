#!/usr/bin/env swift
//
// Renders Tower's app icon to a single 1024×1024 PNG.
//
// The icon is generated from this script rather than committed as an opaque
// binary with no source, so it can be adjusted deliberately — change a number
// here, re-run, and the diff explains itself. Run with:
//
//   swift scripts/make-app-icon.swift Tower/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Design, and why:
//
// - **Three white bars on a blue gradient.** Tower is a client for a storage
//   array; a stack of drive bays is the most direct mark for that, and it
//   survives being shrunk to 60pt because it is three shapes, not a drawing.
// - **System blue**, not a brand colour. Tower should feel like a system app,
//   with no cross-platform tells, and the accent is the platform's own.
// - **One green LED on the top bay**, echoing `StateDot`'s running colour — the
//   only non-white element, and the only thing that says "this is about a
//   machine that is up".
// - **No alpha.** App Store icons must be fully opaque; a transparent corner is
//   a rejection, and the OS applies the rounded-rect mask itself.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024.0

guard CommandLine.arguments.count > 1 else {
  FileHandle.standardError.write(Data("usage: make-app-icon.swift <output.png>\n".utf8))
  exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
  data: nil,
  width: Int(side),
  height: Int(side),
  bitsPerComponent: 8,
  bytesPerRow: 0,
  space: colorSpace,
  // `noneSkipLast`, not `premultipliedLast`: the icon must be opaque, and this
  // makes that structural rather than something to remember.
  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
  FileHandle.standardError.write(Data("could not create bitmap context\n".utf8))
  exit(1)
}

// Background: a vertical system-blue gradient. Light at the top so the mark
// reads against it at every size.
let top = CGColor(red: 0.039, green: 0.518, blue: 1.0, alpha: 1)      // #0A84FF
let bottom = CGColor(red: 0.0, green: 0.278, blue: 0.784, alpha: 1)   // #0047C8
guard let gradient = CGGradient(
  colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1]
) else { exit(1) }
context.drawLinearGradient(
  gradient,
  start: CGPoint(x: 0, y: side),
  end: CGPoint(x: 0, y: 0),
  options: []
)

// Three drive bays, centred as one block.
let bayWidth = 560.0
let bayHeight = 132.0
let bayGap = 24.0
let corner = 30.0
let blockHeight = bayHeight * 3 + bayGap * 2
let originX = (side - bayWidth) / 2
let originY = (side - blockHeight) / 2

for index in 0..<3 {
  let y = originY + Double(index) * (bayHeight + bayGap)
  let rect = CGRect(x: originX, y: y, width: bayWidth, height: bayHeight)
  context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
  context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
  context.fillPath()

  // The LED, on the top bay only (index 2, since y grows upward here). Green,
  // matching `StateDot`'s running colour — the one element that says the machine
  // is up rather than merely present.
  if index == 2 {
    let dot = CGRect(x: originX + 60, y: y + bayHeight / 2 - 22, width: 44, height: 44)
    context.addEllipse(in: dot)
    context.setFillColor(CGColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)) // system green
    context.fillPath()
  }
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else {
  FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
  exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
  FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
  exit(1)
}
print("wrote \(output.path)")
