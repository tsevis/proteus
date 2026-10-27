import Foundation
import ImageIO

/// When a photo was taken, from its EXIF data.
public enum PhotoDate {
    public static func read(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: stamp)
    }
}

/// Adds or removes a Finder tag. Tags never change a file's name or contents.
public enum FileTags {
    public static func add(_ tag: String, to items: [FoundItem]) -> ActionReport {
        update(items) { tags in
            tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } ? tags : tags + [tag]
        }
    }

    public static func remove(_ tag: String, from items: [FoundItem]) -> ActionReport {
        update(items) { tags in tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame } }
    }

    private static func update(_ items: [FoundItem], _ change: ([String]) -> [String]) -> ActionReport {
        var succeeded = 0
        var failures: [String] = []
        for item in items {
            let fresh = URL(fileURLWithPath: item.url.path)
            do {
                let current = try fresh.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
                let updated = change(current)
                guard updated != current else { continue }
                try (fresh as NSURL).setResourceValue(updated, forKey: .tagNamesKey)
                succeeded += 1
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return ActionReport(succeeded: succeeded, failures: failures)
    }
}

/// Comma-separated values, quoted where a field needs it (RFC 4180).
public enum CSVExport {
    public static func document(_ rows: [[String]]) -> String {
        rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func field(_ value: String) -> String {
        let needsQuotes = value.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        return needsQuotes ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }
}
