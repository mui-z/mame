#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
#if canImport(Glibc)
    import Glibc
#endif
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
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let directoryURL = URL(fileURLWithPath: directory, relativeTo: workingDirectory).standardizedFileURL

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
                    do {
                        let refreshedDefinition = try MockRouteLoader.loadDefinition(from: standardizedURL)
                        if let methodOverride, refreshedDefinition.method != methodOverride {
                            logger.warning(
                                "Mock route method does not match registered method",
                                metadata: [
                                    "file": "\(standardizedURL.path)",
                                    "registered": "\(methodOverride.rawValue)",
                                    "configured": "\(refreshedDefinition.method.rawValue)",
                                ],
                            )
                        } else if methodOverride == nil, refreshedDefinition.method != selectedMethod {
                            logger.warning(
                                "Mock route method does not match registered method",
                                metadata: [
                                    "file": "\(standardizedURL.path)",
                                    "registered": "\(selectedMethod.rawValue)",
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
                        if isFileMissing(error) {
                            logger.warning(
                                "Fixture missing",
                                metadata: [
                                    "file": "\(standardizedURL.path)",
                                    "reason": "File not found",
                                ],
                            )
                            return MockRouteResponseFactory.makeJSONResponse(
                                status: .notFound,
                                body: "{\"error\":\"Fixture not found\"}",
                            )
                        } else {
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
        let lastIndex = components.indices.last!
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

private func isFileMissing(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
        return true
    }
    #if canImport(Glibc)
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == ENOENT {
            return true
        }
    #endif
    return false
}
