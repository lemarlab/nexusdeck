import AppKit

/// Images read from disk once and kept in a bounded cache (icons, key pictures, backgrounds).
/// Entries are reloaded when the file changes; the cache is emptied under memory pressure.
enum ImageCache {
    private final class Entry { let image: NSImage; let modified: Date; init(_ i: NSImage, _ m: Date) { image = i; modified = m } }
    private static let cache: NSCache<NSString, Entry> = {
        let c = NSCache<NSString, Entry>()
        c.countLimit = 300
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    static func image(atPath path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        if let e = cache.object(forKey: path as NSString), e.modified == modified { return e.image }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        let px = img.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
        cache.setObject(Entry(img, modified), forKey: path as NSString, cost: max(1, px * 4))
        return img
    }

    static func image(at url: URL) -> NSImage? { image(atPath: url.path) }
}
