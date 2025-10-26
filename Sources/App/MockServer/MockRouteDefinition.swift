#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import HTTPTypes
import Hummingbird

struct MockRouteDefinition {
    let method: HTTPRequest.Method
    let status: HTTPResponse.Status
    let latencyMilliseconds: Int?
    let responseBody: String

    /// Returns latency in nanoseconds if it can be represented safely.
    var latencyNanoseconds: UInt64? {
        guard let latencyMilliseconds else { return nil }
        let multiplier: UInt64 = 1_000_000
        guard latencyMilliseconds >= 0 else { return nil }
        let milliseconds = UInt64(latencyMilliseconds)
        if milliseconds > UInt64.max / multiplier {
            return nil
        }
        return milliseconds * multiplier
    }

    func makeResponse() -> Response {
        MockRouteResponseFactory.makeJSONResponse(status: status, body: responseBody)
    }
}

enum MockRouteLoaderError: LocalizedError, CustomStringConvertible {
    case invalidFormat(String)
    case missingField(String)
    case unsupportedMethod(String)
    case invalidStatus(String)
    case invalidLatency(String)
    case invalidJSON

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case let .invalidFormat(context):
            "Invalid YAML structure: \(context)"
        case let .missingField(field):
            "Missing required field '\(field)'"
        case let .unsupportedMethod(method):
            "Unsupported HTTP method '\(method)'"
        case let .invalidStatus(value):
            "Invalid status code '\(value)'"
        case let .invalidLatency(value):
            "Invalid latency value '\(value)'"
        case .invalidJSON:
            "JSON field is not encodable"
        }
    }
}

enum MockRouteResponseFactory {
    static func makeJSONResponse(status: HTTPResponse.Status, body: String) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json; charset=utf-8"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(string: body)))
    }
}
