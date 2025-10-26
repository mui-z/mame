#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import Darwin
import HTTPTypes
import Hummingbird
import Logging

enum MockRouteRegistrar {
    static func registerRoutes(
        from directory: String,
        on router: Router<AppRequestContext>,
        logger: Logger,
    ) {
        let fileManager = FileManager.default
        let directoryURL = resolveDirectoryURL(for: directory)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            logger.debug("Mock response directory not found", metadata: ["directory": "\(directoryURL.path)"])
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else {
            logger.warning("Failed to enumerate mock response directory", metadata: ["directory": "\(directoryURL.path)"])
            return
        }

        for case let fileURL as URL in enumerator {
            let standardizedURL = fileURL.standardizedFileURL
            let fileExtension = standardizedURL.pathExtension.lowercased()
            guard fileExtension == "yml" || fileExtension == "yaml" else { continue }

            do {
                let definition = try MockRouteLoader.loadDefinition(from: standardizedURL)
                let (routePath, methodOverride) = buildRoute(for: standardizedURL, relativeTo: directoryURL)
                let selectedMethod = methodOverride ?? definition.method
                if let methodOverride, methodOverride != definition.method {
                    logger.warning(
                        "Method override from filename",
                        metadata: [
                            "file": "\(standardizedURL.path)",
                            "method": "\(methodOverride.rawValue)",
                            "yaml": "\(definition.method.rawValue)",
                        ],
                    )
                }

                router.on(RouterPath(routePath), method: selectedMethod) { _, _ in
                    if let response = try await makeResponse(
                        from: standardizedURL,
                        methodOverride: methodOverride,
                        requestMethod: selectedMethod,
                        logger: logger,
                        enforceMethodMatch: false,
                    ) {
                        return response
                    }
                    throw HTTPError(.notFound)
                }

                logger.debug(
                    "Registered mock route",
                    metadata: [
                        "path": "\(routePath)",
                        "method": "\(selectedMethod.rawValue)",
                        "source": "\(standardizedURL.path)",
                    ],
                )
            } catch {
                logger.warning(
                    "Skipping mock route",
                    metadata: [
                        "file": "\(standardizedURL.path)",
                        "reason": "\(error.localizedDescription)",
                    ],
                )
            }
        }
    }

    private static func buildRoute(for fileURL: URL, relativeTo root: URL) -> (path: String, method: HTTPRequest.Method?) {
        let withoutExtension = fileURL.deletingPathExtension()
        let relative = stripPrefix(withoutExtension.path, prefix: root.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !relative.isEmpty else { return ("/", nil) }

        var components = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else { return ("/", nil) }

        var methodOverride: HTTPRequest.Method?
        let lastIndex = components.index(before: components.endIndex)
        let lastComponent = components[lastIndex]
        if let hashIndex = lastComponent.firstIndex(of: "#") {
            let suffix = lastComponent[lastComponent.index(after: hashIndex)...]
            let base = lastComponent[..<hashIndex]
            if let method = HTTPRequest.Method(rawValue: suffix.uppercased()) {
                methodOverride = method
            }
            components[lastIndex] = base
        }

        let normalizedPath = "/" + components.joined(separator: "/")
        return (normalizedPath, methodOverride)
    }

    private static func stripPrefix(_ string: String, prefix: String) -> String {
        guard string.hasPrefix(prefix) else { return string }
        return String(string.dropFirst(prefix.count))
    }
}

extension MockRouteRegistrar {
    static func resolveDirectoryURL(for directory: String) -> URL {
        let fileManager = FileManager.default
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        return URL(fileURLWithPath: directory, relativeTo: workingDirectory).standardizedFileURL
    }

    static func makeDynamicResponse(
        for requestPath: String,
        method: HTTPRequest.Method,
        directoryURL: URL,
        logger: Logger,
    ) async throws -> Response? {
        guard
            let (fileURL, methodOverride) = findFixture(
                for: requestPath,
                method: method,
                root: directoryURL,
            )
        else {
            return nil
        }
        return try await makeResponse(
            from: fileURL,
            methodOverride: methodOverride,
            requestMethod: method,
            logger: logger,
            enforceMethodMatch: methodOverride == nil,
        ).map { response in
            logger.debug(
                "Dynamically served mock route",
                metadata: [
                    "path": "\(requestPath)",
                    "method": "\(method.rawValue)",
                    "source": "\(fileURL.path)",
                ],
            )
            return response
        }
    }

    private static func findFixture(
        for requestPath: String,
        method: HTTPRequest.Method,
        root: URL,
    ) -> (url: URL, methodOverride: HTTPRequest.Method?)? {
        guard let relativePath = normalizedRelativePath(from: requestPath) else {
            return nil
        }
        let fileManager = FileManager.default
        let methodSuffixes = [method.rawValue.lowercased(), method.rawValue.uppercased()]
        for suffix in methodSuffixes {
            for ext in ["yml", "yaml"] {
                let candidate = root
                    .appendingPathComponent("\(relativePath)#\(suffix)")
                    .appendingPathExtension(ext)
                if fileManager.fileExists(atPath: candidate.path) {
                    return (candidate.standardizedFileURL, method)
                }
            }
        }
        for ext in ["yml", "yaml"] {
            let candidate = root
                .appendingPathComponent(relativePath)
                .appendingPathExtension(ext)
            if fileManager.fileExists(atPath: candidate.path) {
                return (candidate.standardizedFileURL, nil)
            }
        }
        return nil
    }

    private static func normalizedRelativePath(from requestPath: String) -> String? {
        let decoded = requestPath.removingPercentEncoding ?? requestPath
        let trimmed = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        var sanitized: [String] = []
        for component in components {
            switch component {
            case ".":
                continue
            case "..":
                return nil
            default:
                sanitized.append(component)
            }
        }
        guard !sanitized.isEmpty else { return nil }
        return sanitized.joined(separator: "/")
    }

    private static func makeResponse(
        from fileURL: URL,
        methodOverride: HTTPRequest.Method?,
        requestMethod: HTTPRequest.Method,
        logger: Logger,
        enforceMethodMatch: Bool,
    ) async throws -> Response? {
        do {
            let definition = try MockRouteLoader.loadDefinition(from: fileURL)
            if let methodOverride {
                if methodOverride != definition.method {
                    logger.warning(
                        "Method override from filename",
                        metadata: [
                            "file": "\(fileURL.path)",
                            "method": "\(methodOverride.rawValue)",
                            "yaml": "\(definition.method.rawValue)",
                        ],
                    )
                }
            } else if definition.method != requestMethod {
                if enforceMethodMatch {
                    return nil
                }
                logger.warning(
                    "Mock route method does not match registered method",
                    metadata: [
                        "file": "\(fileURL.path)",
                        "registered": "\(requestMethod.rawValue)",
                        "configured": "\(definition.method.rawValue)",
                    ],
                )
            }

            if let milliseconds = definition.latencyMilliseconds {
                if let nanoseconds = definition.latencyNanoseconds {
                    if nanoseconds > 0 {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    }
                } else {
                    logger.warning(
                        "Configured latency too large to apply",
                        metadata: [
                            "file": "\(fileURL.path)",
                            "latency": "\(milliseconds)",
                        ],
                    )
                }
            }

            return definition.makeResponse()
        } catch {
            if isFileMissing(error) {
                logger.warning(
                    "Fixture missing",
                    metadata: [
                        "file": "\(fileURL.path)",
                        "reason": "File not found",
                    ],
                )
                return MockRouteResponseFactory.makeJSONResponse(
                    status: .notFound,
                    body: "{\"error\":\"Fixture not found\"}",
                )
            }
            logger.error(
                "Failed to reload mock route",
                metadata: [
                    "file": "\(fileURL.path)",
                    "reason": "\(error.localizedDescription)",
                ],
            )
            let errorBody = (try? MockRouteLoaderErrorPayload.build(reason: error.localizedDescription))
                ?? "{\"error\":\"Failed to load mock response\"}"
            return MockRouteResponseFactory.makeJSONResponse(status: .internalServerError, body: errorBody)
        }
    }
}

struct DynamicFixtureMiddleware<Context: RequestContext>: RouterMiddleware {
    let directoryURL: URL
    let logger: Logger

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response,
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError where error.status == .notFound {
            if let response = try await MockRouteRegistrar.makeDynamicResponse(
                for: request.uri.path,
                method: request.method,
                directoryURL: directoryURL,
                logger: logger,
            ) {
                return response
            }
            throw error
        }
    }
}

private enum MockRouteLoaderErrorPayload {
    static func build(reason: String) throws -> String {
        let payload: [String: String] = [
            "error": "Failed to load mock response",
            "details": reason,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw MockRouteLoaderError.invalidJSON
        }
        return string
    }
}

private func isFileMissing(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
        return true
    }
    return false
}
