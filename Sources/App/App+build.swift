#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import HTTPTypes
import Hummingbird
import Logging
import Yams

/// Application arguments protocol. We use a protocol so we can call
/// `buildApplication` inside Tests as well as in the App executable.
/// Any variables added here also have to be added to `App` in App.swift and
/// `TestArguments` in AppTest.swift
package protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var logLevel: Logger.Level? { get }
}

// Request context used by application
typealias AppRequestContext = BasicRequestContext

///  Build application
/// - Parameter arguments: application arguments
func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    let environment = Environment()
    let logger = {
        var logger = Logger(label: "mame")
        logger.logLevel =
            arguments.logLevel ??
            environment.get("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ??
            .info
        return logger
    }()
    let router = try buildRouter(logger: logger)
    let app = Application(
        router: router,
        configuration: .init(
            address: .hostname(arguments.hostname, port: arguments.port),
            serverName: "mame",
        ),
        logger: logger,
    )
    return app
}

/// Build router
func buildRouter(logger: Logger) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    // Add middleware
    router.addMiddleware {
        // logging middleware
        LogRequestsMiddleware(.info)
    }
    // Add default endpoint
    router.get("/") { _, _ in
        "Hello!"
    }
    registerMockRoutes(from: "sample", on: router, logger: logger)
    return router
}

private struct MockRouteDefinition {
    let method: HTTPRequest.Method
    let status: HTTPResponse.Status
    let latencyMilliseconds: Int?
    let responseBody: String
}

private enum MockRouteLoaderError: LocalizedError, CustomStringConvertible {
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

private func registerMockRoutes(
    from directory: String,
    on router: Router<AppRequestContext>,
    logger: Logger,
) {
    let fileManager = FileManager.default
    let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let directoryURL = URL(fileURLWithPath: directory, relativeTo: workingDirectory).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        logger.debug("Mock response directory not found", metadata: ["directory": "\(directoryURL.path)"])
        return
    }
    guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
        logger.warning("Failed to enumerate mock response directory", metadata: ["directory": "\(directoryURL.path)"])
        return
    }

    for case let fileURL as URL in enumerator {
        let standardizedURL = fileURL.standardizedFileURL
        let fileExtension = standardizedURL.pathExtension.lowercased()
        guard fileExtension == "yml" || fileExtension == "yaml" else { continue }
        do {
            let definition = try loadMockRouteDefinition(from: standardizedURL)
            let routePath = buildRoutePath(for: standardizedURL, relativeTo: workingDirectory)
            let responseBody = definition.responseBody
            router.on(RouterPath(routePath), method: definition.method) { _, _ in
                if let latency = definition.latencyMilliseconds, latency > 0 {
                    let safeLatency = UInt64(latency)
                    try await Task.sleep(nanoseconds: safeLatency * 1_000_000)
                }
                let buffer = ByteBuffer(string: responseBody)
                var headers = HTTPFields()
                headers[.contentType] = "application/json; charset=utf-8"
                return Response(
                    status: definition.status,
                    headers: headers,
                    body: .init(byteBuffer: buffer),
                )
            }
            logger.debug("Registered mock route", metadata: [
                "path": "\(routePath)",
                "method": "\(definition.method.rawValue)",
                "source": "\(standardizedURL.path)",
            ])
        } catch {
            logger.warning("Skipping mock route", metadata: [
                "file": "\(standardizedURL.path)",
                "reason": "\(error.localizedDescription)",
            ])
        }
    }
}

private func loadMockRouteDefinition(from fileURL: URL) throws -> MockRouteDefinition {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    guard let raw = try Yams.load(yaml: contents) as? [String: Any] else {
        throw MockRouteLoaderError.invalidFormat(fileURL.lastPathComponent)
    }

    let method = try parseMethod(from: raw["method"], file: fileURL)
    let status = try parseStatus(from: raw["status"], file: fileURL)
    let latency = try parseLatency(from: raw["latency"], file: fileURL)

    guard let jsonValue = raw["json"] else {
        throw MockRouteLoaderError.missingField("json")
    }
    let responseBody = try encodeJSON(from: jsonValue)

    return MockRouteDefinition(
        method: method,
        status: status,
        latencyMilliseconds: latency,
        responseBody: responseBody,
    )
}

private func parseMethod(from value: Any?, file _: URL) throws -> HTTPRequest.Method {
    guard let raw = value as? String, !raw.isEmpty else {
        throw MockRouteLoaderError.missingField("method")
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

private func parseStatus(from value: Any?, file _: URL) throws -> HTTPResponse.Status {
    guard let value else {
        throw MockRouteLoaderError.missingField("status")
    }
    if let intValue = value as? Int {
        return HTTPResponse.Status(code: intValue)
    }
    if let stringValue = value as? String, let intValue = Int(stringValue) {
        return HTTPResponse.Status(code: intValue)
    }
    throw MockRouteLoaderError.invalidStatus("\(value)")
}

private func parseLatency(from value: Any?, file _: URL) throws -> Int? {
    guard let value else { return nil }
    if let intValue = value as? Int {
        return intValue
    }
    if let stringValue = value as? String, let intValue = Int(stringValue) {
        return intValue
    }
    throw MockRouteLoaderError.invalidLatency("\(value)")
}

private func encodeJSON(from value: Any) throws -> String {
    if let stringValue = value as? String {
        return stringValue
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    if value is NSNull {
        return "null"
    }
    if JSONSerialization.isValidJSONObject(value) {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw MockRouteLoaderError.invalidJSON
        }
        return string
    }
    throw MockRouteLoaderError.invalidJSON
}

private func buildRoutePath(for fileURL: URL, relativeTo root: URL) -> String {
    let trimmedPath = stripPrefix(fileURL.deletingPathExtension().path, prefix: root.path)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmedPath.isEmpty else { return "/" }
    return "/\(trimmedPath)"
}

private func stripPrefix(_ string: String, prefix: String) -> String {
    guard string.hasPrefix(prefix) else { return string }
    return String(string.dropFirst(prefix.count))
}
