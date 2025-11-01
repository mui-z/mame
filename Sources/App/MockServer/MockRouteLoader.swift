import Foundation
import HTTPTypes
import Hummingbird
import Logging
import Yams

enum MockRouteLoader {
    static func loadDefinition(from fileURL: URL) throws -> MockRouteDefinition {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        guard let raw = try Yams.load(yaml: contents) as? [String: Any] else {
            throw MockRouteLoaderError.invalidFormat(fileURL.lastPathComponent)
        }

        let method = try parseMethod(from: raw["method"])
        let status = try parseStatus(from: raw["status"])
        let latency = try parseLatency(from: raw["latency"])
        let responseBody = try parseResponseBody(from: raw)

        return MockRouteDefinition(
            method: method,
            status: status,
            latencyMilliseconds: latency,
            responseBody: responseBody,
        )
    }

    private static func parseMethod(from value: Any?) throws -> HTTPRequest.Method {
        guard let raw = value as? String, !raw.isEmpty else {
            return .get
        }
        switch raw.uppercased() {
        case "GET": return .get
        case "POST": return .post
        case "PUT": return .put
        case "PATCH": return .patch
        case "DELETE": return .delete
        case "HEAD": return .head
        case "OPTIONS": return .options
        default:
            throw MockRouteLoaderError.unsupportedMethod(raw)
        }
    }

    private static func parseStatus(from value: Any?) throws -> HTTPResponse.Status {
        guard let value else {
            return try makeStatus(from: 200)
        }
        if let intValue = value as? Int {
            return try makeStatus(from: intValue)
        }
        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return try makeStatus(from: intValue)
        }
        throw MockRouteLoaderError.invalidStatus("\(value)")
    }

    private static func parseLatency(from value: Any?) throws -> Int? {
        guard let value else { return 0 }
        if let intValue = value as? Int {
            return try normalizedLatency(intValue)
        }
        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return try normalizedLatency(intValue)
        }
        throw MockRouteLoaderError.invalidLatency("\(value)")
    }

    private static func parseResponseBody(from raw: [String: Any]) throws -> String {
        if let bodyValue = raw["body"] {
            return try encodeJSON(from: bodyValue)
        }
        throw MockRouteLoaderError.missingField("body")
    }

    private static func encodeJSON(from value: Any) throws -> String {
        if let stringValue = value as? String {
            return stringValue
        }
        return try makeJSONString(from: value)
    }

    private static func makeJSONString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw MockRouteLoaderError.invalidJSON
        }
        return string
    }

    private static func makeStatus(from code: Int) throws -> HTTPResponse.Status {
        guard (100 ... 599).contains(code) else {
            throw MockRouteLoaderError.invalidStatus("\(code)")
        }
        return HTTPResponse.Status(code: code)
    }

    private static func normalizedLatency(_ latency: Int) throws -> Int {
        guard latency >= 0 else {
            throw MockRouteLoaderError.invalidLatency("\(latency)")
        }
        return latency
    }
}
