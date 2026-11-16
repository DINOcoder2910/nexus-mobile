import UIKit
import ImageIO
import UniformTypeIdentifiers

/// A picture put on a board, made ready away from the main thread: at most `maxSide` pixels on its long side (a board shows it a few
/// hundred points wide; the laptop's limit for a pasted image is the same), JPEG unless it has see-through parts (then PNG).
enum BoardImage {
    struct Prepared {
        let data: Data
        let ext: String
        /// In pixels.
        let size: CGSize
    }

    static let maxSide: CGFloat = 2400

    /// From an image file's bytes (a photo picked from the library): read shrunk straight from the file, so the full-size photo is
    /// never decoded. Call off the main thread.
    static func prepare(data: Data) -> Prepared? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // upright, as the camera held it
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return encode(UIImage(cgImage: cg))
    }

    /// From an image already in memory. Call off the main thread.
    static func prepare(image: UIImage) -> Prepared? {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard px.width > 0, px.height > 0 else { return nil }
        let k = min(1, maxSide / max(px.width, px.height))
        if k >= 1, image.imageOrientation == .up { return encode(image) }
        let size = CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = !hasAlpha(image)
        let small = UIGraphicsImageRenderer(size: size, format: f).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return encode(small)
    }

    static func hasAlpha(_ img: UIImage) -> Bool {
        guard let a = img.cgImage?.alphaInfo else { return false }
        return a == .first || a == .last || a == .premultipliedFirst || a == .premultipliedLast
    }

    private static func encode(_ img: UIImage) -> Prepared? {
        let alpha = hasAlpha(img)
        guard let data = alpha ? img.pngData() : img.jpegData(compressionQuality: 0.85) else { return nil }
        let size = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        return Prepared(data: data, ext: alpha ? ".png" : ".jpg", size: size)
    }
}
