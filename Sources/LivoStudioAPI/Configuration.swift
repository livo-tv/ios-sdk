import Foundation

/// Production media-svc host. Partners may override for the Dev account.
public enum LivoAPIConfiguration: Sendable {
    public static let productionAPIURL = URL(string: "https://media-svc.livo.tv")!

    public static func normalizeAPIURL(_ url: URL) -> URL {
        var absolute = url.absoluteString
        if absolute.hasSuffix("/") {
            absolute.removeLast()
        }
        return URL(string: absolute) ?? url
    }
}
