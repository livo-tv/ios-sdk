import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String]
    }

    static let lock = NSLock()
    static var stubs: [String: Stub] = [:]
    static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        stubs = [:]
        requests = []
        lock.unlock()
    }

    static func stub(_ pathContains: String, status: Int = 200, json: String) {
        lock.lock()
        stubs[pathContains] = Stub(
            status: status,
            body: Data(json.utf8),
            headers: ["Content-Type": "application/json"]
        )
        lock.unlock()
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            captured.httpBody = Self.read(stream)
        }
        Self.lock.lock()
        Self.requests.append(captured)
        let path = request.url?.absoluteString ?? request.url?.path ?? ""
        let stub = Self.stubs
            .sorted { $0.key.count > $1.key.count }
            .first { path.contains($0.key) }?.value
        Self.lock.unlock()

        guard let stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
