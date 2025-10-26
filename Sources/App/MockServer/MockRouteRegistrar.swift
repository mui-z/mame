#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import Hummingbird
import Logging

enum MockRouteRegistrar {
    static func registerRoutes(
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
                let definition = try MockRouteLoader.loadDefinition(from: standardizedURL)
                let routePath = buildRoutePath(for: standardizedURL, relativeTo: workingDirectory)
                let method = definition.method

                router.on(RouterPath(routePath), method: method) { _, _ in
                    do {
                        let refreshedDefinition = try MockRouteLoader.loadDefinition(from: standardizedURL)
                        if refreshedDefinition.method != method {
                            logger.warning(
                                "Mock route method does not match registered method",
                                metadata: [
                                    "file": "\(standardizedURL.path)",
                                    "registered": "\(method.rawValue)",
                                    "configured": "\(refreshedDefinition.method.rawValue)",
                                ],
                            )
                        }

                        if let milliseconds = refreshedDefinition.latencyMilliseconds {
                            if let nanoseconds = refreshedDefinition.latencyNanoseconds {
                                if nanoseconds > 0 {
                                    try await Task.sleep(nanoseconds: nanoseconds)
                                }
                            } else {
                                logger.warning(
                                    "Configured latency too large to apply",
                                    metadata: [
                                        "file": "\(standardizedURL.path)",
                                        "latency": "\(milliseconds)",
                                    ],
                                )
                            }
                        }

                        return refreshedDefinition.makeResponse()
                    } catch {
                        logger.error(
                            "Failed to reload mock route",
                            metadata: [
                                "file": "\(standardizedURL.path)",
                                "reason": "\(error.localizedDescription)",
                            ],
                        )
                        let errorBody = (try? MockRouteLoaderErrorPayload.build(reason: error.localizedDescription))
                            ?? "{\"error\":\"Failed to load mock response\"}"
                        return MockRouteResponseFactory.makeJSONResponse(status: .internalServerError, body: errorBody)
                    }
                }

                logger.debug("Registered mock route", metadata: [
                    "path": "\(routePath)",
                    "method": "\(definition.method.rawValue)",
                    "source": "\(standardizedURL.path)",
                ])
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

    private static func buildRoutePath(for fileURL: URL, relativeTo root: URL) -> String {
        let trimmedPath = stripPrefix(fileURL.deletingPathExtension().path, prefix: root.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else { return "/" }
        return "/\(trimmedPath)"
    }

    private static func stripPrefix(_ string: String, prefix: String) -> String {
        guard string.hasPrefix(prefix) else { return string }
        return String(string.dropFirst(prefix.count))
    }
}

private enum MockRouteLoaderErrorPayload {
    static func build(reason: String) throws -> String {
        let payload: [String: String] = [
            "error": "Failed to load mock response",
            "details": reason,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw MockRouteLoaderError.invalidJSON
        }
        return string
    }
}
