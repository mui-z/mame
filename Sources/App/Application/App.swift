import ArgumentParser
import Hummingbird
import Logging

@main
struct AppCommand: AsyncParsableCommand, AppArguments {
    static let configuration = CommandConfiguration(
        commandName: "mame",
        abstract: "Filesystem-driven mock HTTP server",
        discussion: """
        Serve JSON responses described in YAML files. By default the current working directory is scanned for
        .yml files; pass --fixtures, --root, or a trailing directory argument to point at a different tree.
        """,
        helpNames: [.long],
    )

    @Option(name: [.customShort("n"), .long])
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong)
    var port: Int = 8080

    @Option(name: .shortAndLong)
    var logLevel: Logger.Level?

    @Option(
        name: [.customShort("f"), .customLong("fixtures"), .customLong("root")],
        help: "Directory containing YAML fixtures (default: current directory)",
    )
    var fixturesOption: String?

    @Argument(help: "Fixture directory (optional override for --fixtures)")
    var fixtureArgument: String?

    var fixtureDirectory: String { fixtureArgument ?? fixturesOption ?? "." }

    func run() async throws {
        let app = try await buildApplication(self)
        try await app.runService()
    }
}

/// Extend `Logger.Level` so it can be used as an argument
#if hasFeature(RetroactiveAttribute)
    extension Logger.Level: @retroactive ExpressibleByArgument {}
#else
    extension Logger.Level: ExpressibleByArgument {}
#endif
