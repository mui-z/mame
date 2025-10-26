#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import HTTPTypes
import Hummingbird
import Logging

struct AccessLogMiddleware<Context: RequestContext>: RouterMiddleware {
    private let logger: Logger
    private let useColor: Bool

    init(logger: Logger, useColor: Bool = AccessLogMiddleware.defaultColorSupport) {
        self.logger = logger
        self.useColor = useColor
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response,
    ) async throws -> Response {
        do {
            let response = try await next(request, context)
            log(request: request, status: response.status)
            return response
        } catch {
            log(request: request, status: .internalServerError)
            throw error
        }
    }

    private func log(request: Request, status: HTTPResponse.Status) {
        let method = request.method.rawValue
        let path = request.uri.path.isEmpty ? "/" : request.uri.path
        let statusText = formattedStatus(code: status.code)
        logger.info("\(method) \(path) -> \(statusText)")
    }

    private func formattedStatus(code: Int) -> String {
        guard useColor else { return String(code) }
        let color = switch code {
        case 200 ..< 300: "\u{001B}[32m" // green
        case 300 ..< 400: "\u{001B}[36m" // cyan
        case 400 ..< 500: "\u{001B}[33m" // yellow
        default: "\u{001B}[31m" // red
        }
        return "\(color)\(code)\u{001B}[0m"
    }

    private static var defaultColorSupport: Bool {
        guard Environment().get("NO_COLOR") == nil else { return false }
        #if canImport(Darwin)
            return isatty(STDERR_FILENO) != 0
        #elseif canImport(Glibc)
            return isatty(STDERR_FILENO) != 0
        #else
            return false
        #endif
    }
}
