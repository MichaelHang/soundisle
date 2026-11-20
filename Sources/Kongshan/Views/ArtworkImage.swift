import AppKit
import SwiftUI

/// Artwork for the album/artist grids and detail pages. Decodes on a background
/// queue, downsamples to roughly twice the display size (retina), and caches
/// results so scrolling a grid of covers never re-decodes full-size images on
/// the main thread — the old `NSImage(contentsOf:)` rows did exactly that.
struct ArtworkImage: View {
    /// Keyed by cover URL; one entry per cover regardless of how many views
    /// show it. Cost limits let the cache evict under memory pressure.
    private static let cache = NSCache<NSURL, NSImage>()

    @Environment(\.theme) private var theme
    let url: URL?
    /// Largest expected display edge, in points; decoding targets 2× this.
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.coverGradient)
            if let image {
                // The Color.clear overlay pattern: the clear square fixes the
                // layout size (a `.fill` image would otherwise size itself by
                // its own aspect ratio under an unbounded height proposal —
                // LazyVGrid cells — and a portrait poster blew up out of its
                // card, covering the neighbours), while the image overflows
                // and gets clipped back to that square.
                Color.clear
                    .overlay(
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipped()
            } else {
                Icons.coverNote
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        let pixelSize = max(size, 24) * 2
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsample(url: url, maxPixelSize: pixelSize)
        }.value
        guard let decoded else { return }
        Self.cache.setObject(decoded, forKey: url as NSURL)
        image = decoded
    }

    /// CGImageSource thumbnailing: decodes straight to the target size instead
    /// of loading a full-resolution image and scaling it afterwards.
    private nonisolated static func downsample(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}
