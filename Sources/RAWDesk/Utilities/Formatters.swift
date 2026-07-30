import Foundation

public enum DisplayFormatters {
    public static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f
    }()

    public static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    public static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    public static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        return dateFormatter.string(from: value)
    }

    public static func shutter(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        if value >= 1 { return String(format: "%.1f s", value) }
        let denom = Int((1.0 / value).rounded())
        return "1/\(denom) s"
    }

    public static func aperture(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "f/%.1f", value)
    }

    public static func focalLength(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f mm", value)
    }

    public static func iso(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "ISO \(value)"
    }

    public static func exposureBias(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.2f EV", value)
    }

    public static func dimensions(_ w: Int?, _ h: Int?) -> String {
        guard let w, let h else { return "—" }
        return "\(w) × \(h)"
    }

    public static func placeholder(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }
}
