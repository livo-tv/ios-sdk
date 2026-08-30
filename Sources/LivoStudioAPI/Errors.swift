import Foundation

public struct StudioAPIError: Error, Sendable, LocalizedError {
    public var status: Int
    public var message: String
    public var body: Data?

    public init(status: Int, message: String, body: Data? = nil) {
        self.status = status
        self.message = message
        self.body = body
    }

    public var errorDescription: String? { message }

    public var code: String? {
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? String
        else { return nil }
        return error
    }

    public var isEnded: Bool { status == 404 || status == 410 }
}

enum StudioJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    static func errorMessage(status: Int, data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String,
           !error.isEmpty
        {
            return error
        }
        return "Studio API \(status)"
    }
}
