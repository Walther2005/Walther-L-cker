import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

/// Berechnet das Effektbild (komplett verpixelt / weichgezeichnet / schwarz),
/// das später nur dort durchscheint, wo gemalt wurde.
enum EffectRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ effect: Effect, strength: Double, on image: CGImage) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let input = CIImage(cgImage: image)
        let output: CIImage

        switch effect {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float(max(3, strength))
            filter.center = .zero
            output = filter.outputImage ?? input
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float(max(2, strength))
            output = filter.outputImage ?? input
        case .blackout:
            output = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.08))
        }

        let space = Compositor.rgbSpace(for: image)
        return context.createCGImage(output.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: space)
    }
}

enum Compositor {
    static func rgbSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static func rgbContext(width: Int, height: Int, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Graustufen-Maske: schwarz = unverändert, weiß = Effekt.
    static func makeMask(width: Int, height: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        return ctx
    }

    static func mask(width: Int, height: Int, rects: [CGRect]) -> CGImage? {
        guard let ctx = makeMask(width: width, height: height) else { return nil }
        for r in rects { ctx.fill(r.integral) }
        return ctx.makeImage()
    }

    /// Legt das Effektbild durch die Maske über das Grundbild – das Ergebnis ist ein neues, flaches Bild.
    /// Der Originalinhalt unter dem Effekt ist darin nicht mehr enthalten.
    static func composite(base: CGImage, effect: CGImage, mask: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        guard let ctx = rgbContext(width: base.width, height: base.height, space: rgbSpace(for: base)) else { return nil }
        ctx.draw(base, in: rect)
        ctx.clip(to: rect, mask: mask)
        ctx.draw(effect, in: rect)
        return ctx.makeImage()
    }

    /// Bringt beliebige Bilder in ein einheitliches 8-Bit-RGBA-Format.
    static func normalized(_ image: CGImage) -> CGImage {
        if image.colorSpace?.model == .rgb, image.bitsPerComponent == 8, image.bitsPerPixel == 32 { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = rgbContext(width: image.width, height: image.height, space: rgbSpace(for: image)) else { return image }
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    static func flattened(_ image: CGImage, background: CGColor) -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = rgbContext(width: image.width, height: image.height, space: rgbSpace(for: image)) else { return image }
        ctx.setFillColor(background)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }
}

enum ImageFiles {
    /// Lädt ein Bild (inkl. EXIF-Drehung) und ermittelt seine Größe in Punkten (Retina-DPI berücksichtigt).
    static func load(url: URL) -> (CGImage, CGSize)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]

        if let orientation = props[kCGImagePropertyOrientation] as? UInt32, orientation != 1 {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height)
            ]
            if let rotated = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { image = rotated }
        }

        image = Compositor.normalized(image)
        var factor = 1.0
        if let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 72 { factor = dpi / 72 }
        return (image, CGSize(width: Double(image.width) / factor, height: Double(image.height) / factor))
    }

    static func cgImage(from nsImage: NSImage) -> CGImage? {
        var w = 0, h = 0
        for rep in nsImage.representations { w = max(w, rep.pixelsWide); h = max(h, rep.pixelsHigh) }
        var rect = CGRect(x: 0, y: 0,
                          width: w > 0 ? CGFloat(w) : nsImage.size.width,
                          height: h > 0 ? CGFloat(h) : nsImage.size.height)
        guard let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return Compositor.normalized(cg)
    }

    @discardableResult
    static func write(_ image: CGImage, pointSize: CGSize, to url: URL, type: UTType) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        let scale = pointSize.width > 0 ? Double(image.width) / Double(pointSize.width) : 1
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale
        ]
        var output = image
        if type == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = 0.9
            output = Compositor.flattened(image, background: CGColor(gray: 1, alpha: 1))
        }
        CGImageDestinationAddImage(dest, output, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}

enum Clipboard {
    static func write(_ image: CGImage, pointSize: CGSize) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize
        let pb = NSPasteboard.general
        pb.declareTypes([.png, .tiff], owner: nil)
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }
}
