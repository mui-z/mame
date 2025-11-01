#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import Hummingbird
import Logging

package protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var logLevel: Logger.Level? { get }
    var fixtureDirectory: String { get }
}

typealias AppRequestContext = BasicRequestContext

func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    let environment = Environment()
    let logger = {
        var logger = Logger(label: "neko")
        logger.logLevel =
            arguments.logLevel ??
            environment.get("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ??
            .info
        return logger
    }()

    let router = try buildRouter(logger: logger, fixtureDirectory: arguments.fixtureDirectory)
    return Application(
        router: router,
        configuration: .init(
            address: .hostname(arguments.hostname, port: arguments.port),
            serverName: "neko",
        ),
        logger: logger,
    )
}

func buildRouter(logger: Logger, fixtureDirectory: String) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    let fixturesURL = MockRouteRegistrar.resolveDirectoryURL(for: fixtureDirectory)
    router.addMiddleware {
        AccessLogMiddleware(logger: logger)
    }
    router.addMiddleware {
        DynamicFixtureMiddleware(directoryURL: fixturesURL, logger: logger)
    }

    router.get("/") { _, _ in
        "Hello!"
    }

    router.get("/health") { _, _ in
        HealthResponse(
            status: "ok",
            uptime: ProcessInfo.processInfo.systemUptime,
            version: "1.0.0",
        )
    }

    MockRouteRegistrar.registerRoutes(from: fixtureDirectory, on: router, logger: logger)
    return router
}
