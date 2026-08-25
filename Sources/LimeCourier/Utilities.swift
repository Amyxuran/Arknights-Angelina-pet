import AppKit
import Foundation

enum ResourceLocator {
    static func url(for name: String, extension ext: String, subdirectory: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let candidates = [
            executableURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
        for root in candidates {
            let url = root.appendingPathComponent(subdirectory).appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

extension NSView {
    func renderedPNGData() -> Data? {
        layoutSubtreeIfNeeded()
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
