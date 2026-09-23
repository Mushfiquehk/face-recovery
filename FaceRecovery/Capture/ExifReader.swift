import Foundation
import ImageIO

/// Reads the capture timestamp a photo carries. A date that comes from here is authoritative;
/// a date that does not marks the scan Date-Adjusted.
enum ExifReader {
    static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            if let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               let date = parse(original, offset: offset) {
                return date
            }
            if let digitised = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
               let date = parse(digitised, offset: offset) {
                return date
            }
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let dateTime = tiff[kCGImagePropertyTIFFDateTime] as? String {
            return parse(dateTime, offset: nil)
        }

        return nil
    }

    /// EXIF timestamps are local wall-clock with no zone. Without an explicit offset the only
    /// defensible reading is the device's current zone, which is right for the usual case of
    /// backfilling your own photos taken where you live.
    private static func parse(_ value: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = offset.flatMap(timeZone(fromOffset:)) ?? .current
        return formatter.date(from: value)
    }

    private static func timeZone(fromOffset offset: String) -> TimeZone? {
        let parts = offset.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else {
            return nil
        }
        let sign = offset.hasPrefix("-") ? -1 : 1
        return TimeZone(secondsFromGMT: hours * 3600 + sign * minutes * 60)
    }
}
