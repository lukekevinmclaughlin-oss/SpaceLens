import SwiftUI

/// Broad file categories used for the type breakdown and the "colour by type"
/// chart mode. Extension-based classification — cheap and good enough for a
/// storage overview.
enum FileCategory: String, CaseIterable, Identifiable {
    case images, video, audio, archives, code, documents, apps, data, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .archives: return "Archives"
        case .code: return "Code"
        case .documents: return "Documents"
        case .apps: return "Apps"
        case .data: return "Data"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .images: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .archives: return "shippingbox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .documents: return "doc.richtext"
        case .apps: return "app.badge"
        case .data: return "cylinder.split.1x2"
        case .other: return "doc"
        }
    }

    var color: Color {
        switch self {
        case .images:    return Color(red: 0.30, green: 0.85, blue: 0.70)
        case .video:     return Color(red: 0.62, green: 0.42, blue: 0.98)
        case .audio:     return Color(red: 0.98, green: 0.45, blue: 0.72)
        case .archives:  return Color(red: 1.00, green: 0.66, blue: 0.28)
        case .code:      return Color(red: 0.24, green: 0.80, blue: 0.98)
        case .documents: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .apps:      return Color(red: 0.55, green: 0.60, blue: 0.98)
        case .data:      return Color(red: 0.85, green: 0.80, blue: 0.42)
        case .other:     return Color(red: 0.55, green: 0.60, blue: 0.66)
        }
    }

    static func of(_ ext: String) -> FileCategory {
        switch ext.lowercased() {
        case "jpg","jpeg","png","gif","heic","webp","tiff","tif","bmp","raw","cr2","nef","arw","psd","svg","ico":
            return .images
        case "mp4","mov","avi","mkv","m4v","webm","flv","wmv","mpg","mpeg","prores","braw":
            return .video
        case "mp3","wav","aac","flac","m4a","aiff","ogg","wma","alac","aif":
            return .audio
        case "zip","dmg","tar","gz","tgz","7z","rar","pkg","bz2","xz","iso","cab":
            return .archives
        case "swift","js","ts","tsx","jsx","py","rs","go","c","cpp","cc","h","hpp","java","rb","php","cs","kt","m","mm","sh","sql","json","yaml","yml","toml","xml","html","css","scss","lua","dart":
            return .code
        case "pdf","doc","docx","pages","txt","rtf","md","key","ppt","pptx","xls","xlsx","numbers","csv","epub","odt":
            return .documents
        case "app","ipa","apk","exe":
            return .apps
        case "db","sqlite","sqlite3","dat","bin","cache","log","idx","pack","bundle":
            return .data
        default:
            return .other
        }
    }

    static func of(node: FileNode) -> FileCategory {
        node.isDirectory ? node.dominantCategory : of(node.url.pathExtension)
    }
}

struct CategoryTotal: Identifiable {
    let category: FileCategory
    var bytes: Int64
    var count: Int
    var id: String { category.id }
}

extension SmartFinders {
    /// Space grouped by file category under `root` (files only), sorted largest
    /// first. Skips empty categories.
    static func categoryBreakdown(in root: FileNode) -> [CategoryTotal] {
        var files: [FileNode] = []
        root.flattenedFiles(into: &files)
        var totals: [FileCategory: (Int64, Int)] = [:]
        for f in files {
            let cat = FileCategory.of(f.url.pathExtension)
            let cur = totals[cat] ?? (0, 0)
            totals[cat] = (cur.0 + f.size, cur.1 + 1)
        }
        return totals
            .map { CategoryTotal(category: $0.key, bytes: $0.value.0, count: $0.value.1) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }
}
