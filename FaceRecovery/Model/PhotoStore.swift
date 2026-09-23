import Foundation
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
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
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
        try data.write(to: url(for: filename), options: .atomic)
        return filename
    }

    static func load(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    /// The upload copy: long edge capped and JPEG-compressed per ScoringConfiguration.
    /// The stored photo keeps its full resolution so a future re-score is not degraded twice.
    static func scoringPayload(for image: UIImage) throws -> Data {
        let longEdge = max(image.size.width, image.size.height)
        let scale = longEdge > ScoringConfiguration.imageLongEdge
            ? ScoringConfiguration.imageLongEdge / longEdge
            : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        guard let data = resized.jpegData(compressionQuality: ScoringConfiguration.jpegQuality) else {
            throw ScoringError.imageEncodingFailed
        }
        return data
    }
}
