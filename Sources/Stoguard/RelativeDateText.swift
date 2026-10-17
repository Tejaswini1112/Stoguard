import Foundation

/// Human-readable relative dates for "last modified" labels.
enum RelativeDateText {
    static func label(for date: Date?) -> String? {
        guard let date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 0 { return "Modified today" }
        if days == 1 { return "Modified yesterday" }
        if days < 7 { return "Modified \(days)d ago" }
        if days < 30 { return "Modified \(days / 7)w ago" }
        if days < 365 { return "Modified \(days / 30)mo ago" }
        return "Modified \(days / 365)y ago"
    }

    static func short(for date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
