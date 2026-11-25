import Foundation

/// Decode file URLs from a menu-bar drop. Spaces and non-ASCII survive.
/// `+` is a literal plus, not a space. A path that already exists is kept as-is
/// so a real filename containing "%20" is not decoded too far.
public enum PathDecode {
    public static func decodeDroppedItem(
        _ raw: String,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        if exists(raw) { return raw }
        var current = raw
        var best = raw
        for _ in 0..<3 {
            current = stripFileURL(urlDecodeOnce(current))
            if current.hasPrefix("//") {
                var alternate = "/" + current.dropFirst(2)
                while alternate.hasPrefix("//") {
                    alternate = "/" + alternate.dropFirst(2)
                }
                if exists(alternate) { current = alternate }
            }
            best = current
            if exists(current) { return current }
            if !looksEncoded(current) { break }
        }
        return best
    }

    public static func splitDropped(
        _ input: String,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        var text = input.replacingOccurrences(of: "\r", with: "")
        if text.hasSuffix("\n") { text.removeLast() }
        if text.isEmpty { return [] }
        return text.split(separator: ",", omittingEmptySubsequences: false).compactMap { part in
            let item = String(part)
            if item.isEmpty { return nil }
            let decoded = decodeDroppedItem(item, exists: exists)
            return decoded.isEmpty ? nil : decoded
        }
    }

    /// Files to pass to `chatbar ingest`. A dropped folder contributes its immediate files.
    public static func filesForIngest(
        _ paths: [String],
        isDirectory: (String) -> Bool,
        children: (String) -> [String],
        exists: (String) -> Bool
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ path: String) {
            guard exists(path), !isDirectory(path), seen.insert(path).inserted else { return }
            result.append(path)
        }
        for path in paths {
            let decoded = decodeDroppedItem(path, exists: exists)
            if isDirectory(decoded) {
                if decoded.hasSuffix(".app") { continue }
                for child in children(decoded) {
                    add((decoded as NSString).appendingPathComponent(child))
                }
            } else {
                add(decoded)
            }
        }
        return result
    }

    static func urlDecodeOnce(_ data: String) -> String {
        var bytes: [UInt8] = []
        let scalars = Array(data.utf8)
        var index = 0
        while index < scalars.count {
            if scalars[index] == UInt8(ascii: "%"),
               index + 2 < scalars.count,
               let byte = hexByte(scalars[index + 1], scalars[index + 2]) {
                bytes.append(byte)
                index += 3
                continue
            }
            bytes.append(scalars[index])
            index += 1
        }
        return String(bytes: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
    }

    static func stripFileURL(_ value: String) -> String {
        if value.hasPrefix("file://localhost/") {
            return String(value.dropFirst("file://localhost".count))
        }
        if value.hasPrefix("file://127.0.0.1/") {
            return String(value.dropFirst("file://127.0.0.1".count))
        }
        if value.hasPrefix("file:///") {
            return String(value.dropFirst("file://".count))
        }
        if value.hasPrefix("file://") {
            let rest = String(value.dropFirst("file://".count))
            if rest.hasPrefix("/") { return rest }
            if let slash = rest.firstIndex(of: "/") {
                return String(rest[slash...])
            }
        }
        return value
    }

    static func looksEncoded(_ value: String) -> Bool {
        if value.hasPrefix("file:") { return true }
        let bytes = Array(value.utf8)
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == UInt8(ascii: "%"), hexByte(bytes[index + 1], bytes[index + 2]) != nil {
                return true
            }
            index += 1
        }
        return false
    }

    private static func hexByte(_ high: UInt8, _ low: UInt8) -> UInt8? {
        func nibble(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 55
            case 97...102: return byte - 87
            default: return nil
            }
        }
        guard let hi = nibble(high), let lo = nibble(low) else { return nil }
        return (hi << 4) | lo
    }
}
