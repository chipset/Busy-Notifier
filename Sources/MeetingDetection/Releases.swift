import Foundation

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    private let numbers: [Int]

    public init?(_ tag: String) {
        let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        self.numbers = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
}

public struct PublishedRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease
    }

    public func updateURL(currentVersion: String) -> URL? {
        guard !draft, !prerelease, let incoming = ReleaseVersion(tagName), let current = ReleaseVersion(currentVersion), incoming > current,
              htmlURL.scheme == "https", htmlURL.host?.lowercased() == "github.com", htmlURL.user == nil, htmlURL.password == nil,
              htmlURL.path.hasPrefix("/chipset/Meeting-Busy/releases/tag/") else { return nil }
        return htmlURL
    }
}
