import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
  fputs("usage: normalize_store_png <input> <output>\n", stderr)
  exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL
guard
  let source = CGImageSourceCreateWithURL(sourceURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  fputs("could not decode input PNG\n", stderr)
  exit(1)
}

let bytesPerRow = image.width * 4
guard let context = CGContext(
  data: nil,
  width: image.width,
  height: image.height,
  bitsPerComponent: 8,
  bytesPerRow: bytesPerRow,
  space: CGColorSpaceCreateDeviceRGB(),
  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
    CGImageAlphaInfo.noneSkipLast.rawValue
) else {
  fputs("could not create opaque RGB drawing context\n", stderr)
  exit(1)
}

context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard
  let normalized = context.makeImage(),
  let destination = CGImageDestinationCreateWithURL(outputURL, UTType.png.identifier as CFString, 1, nil)
else {
  fputs("could not create output PNG\n", stderr)
  exit(1)
}
CGImageDestinationAddImage(destination, normalized, nil)
guard CGImageDestinationFinalize(destination) else {
  fputs("could not write output PNG\n", stderr)
  exit(1)
}
