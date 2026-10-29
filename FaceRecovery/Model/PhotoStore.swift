import Foundation
import ImageIO
import UIKit

/// Face Scan photos live on disk, not in SwiftData: a store of base64 blobs would make every
/// history query drag the images with it. `FaceScan.photoFilename` resolves against this.
enum PhotoStore {
    enum StoreError: LocalizedError {
        case encodingFailed
        var errorDescription: String? { "The photo could not be written to disk." }
    }

    /// Application Support rather than Documents: these are app data, not user documents, and
    /// the export is the user-facing copy.
    ///
    /// Photos are only ever read on screen or by Export, so they are unreadable whenever the
    /// phone is locked. The SwiftData store keeps the system default instead, because the
    /// Family Update intent reads it from a Shortcuts automation on a locked phone (ADR 0007).
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return base
    }

    /// Raises photos saved before ADR 0007 to the same protection as new ones. Call at launch;
    /// a file that cannot be changed while the phone is locked is simply retried next launch.
    static func protectExistingPhotos() {
        let manager = FileManager.default
        let folder = directory
        try? manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let path = folder.appendingPathComponent(name).path
            let current = (try? manager.attributesOfItem(atPath: path))?[.protectionKey] as? FileProtectionType
            guard current != .complete else { continue }
            try? manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Writes the full-resolution photo under the scan's id. Returns the filename to store.
    @discardableResult
    static func save(_ image: UIImage, id: UUID) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw StoreError.encodingFailed
        }
        let filename = "\(id.uuidString).jpg"
        try data.write(to: url(for: filename), options: [.atomic, .completeFileProtection])
        return filename
    }

    static func load(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    private static let thumbnails = NSCache<NSString, UIImage>()

    /// A small copy for lists and cards, decoded at the size it is shown rather than at the
    /// camera's full resolution, so History scrolls smoothly. Kept in memory only, never on disk.
    static func thumbnail(_ filename: String, maxPixelSize: Int = 240) -> UIImage? {
        let key = "\(filename)@\(maxPixelSize)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url(for: filename) as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = UIImage(cgImage: cgImage)
        thumbnails.setObject(image, forKey: key)
        return image
    }
}
