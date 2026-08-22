import Foundation
import SwiftUI

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Deterministic, pleasant colour for a node — derived from its name so the same
/// folder keeps the same hue across rescans. Distinct file types get a stable tint.
enum NodePalette {
    static func color(for node: FileNode) -> Color {
        let key = node.isDirectory ? node.name : node.url.pathExtension.lowercased()
        var hasher = Hasher()
        hasher.combine(key)
        let h = Double(abs(hasher.finalize()) % 360) / 360.0
        let sat = node.isDirectory ? 0.52 : 0.42
        let bri = node.isDirectory ? 0.92 : 0.78
        return Color(hue: h, saturation: sat, brightness: bri)
    }

    /// Colour for a node honouring the "colour by type" toggle.
    static func color(for node: FileNode, byType: Bool) -> Color {
        byType ? FileCategory.of(node: node).color : color(for: node)
    }

    static func ringColor(depth: Int, index: Int, total: Int) -> Color {
        let h = total > 0 ? Double(index) / Double(total) : 0
        let sat = 0.55 - Double(depth) * 0.06
        let bri = 0.95 - Double(depth) * 0.05
        return Color(hue: h, saturation: max(0.28, sat), brightness: max(0.6, bri))
    }
}

/// Category icon for a file/folder, shown in lists.
enum NodeIcon {
    static func symbol(for node: FileNode) -> String {
        if node.isDirectory { return "folder.fill" }
        switch node.url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp": return "photo"
        case "mp4", "mov", "avi", "mkv", "m4v", "webm": return "film"
        case "mp3", "wav", "aac", "flac", "m4a", "aiff": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "dmg", "tar", "gz", "7z", "rar", "pkg": return "shippingbox"
        case "app": return "app.badge"
        case "swift", "js", "ts", "py", "rs", "go", "c", "cpp", "h", "java", "rb": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
