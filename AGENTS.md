# Repository Guidelines

## Project Structure & Module Organization
The SwiftPM manifest (`Package.swift`) defines a single executable target. Runtime code is split into `Sources/App/Application` for the CLI entry point, router builder, and request logging (`AccessLogMiddleware`), and `Sources/App/MockServer` for YAML-driven routing helpers (`MockRouteDefinition`, `MockRouteLoader`, `MockRouteRegistrar`). Sample fixtures live under `sample/` and are loaded on every request, so edits take effect without restarting the service. Tests reside in `Tests/AppTests` and exercise routes with HummingbirdTesting and Swift Testing macros.

## Build, Test, and Development Commands
Use `swift build` to compile and surface warnings. Launch the server locally via `swift run mame --hostname 0.0.0.0 --port 8080 --log-level debug --fixtures sample` when running from the repository root. The fixture directory option also answers to `--root`/`-f`, and a positional argument (`swift run mame sample`) is supported. Run `swift test` before committing; CI executes the same command. Container workflows remain `docker build -t mame .` followed by `docker run --rm -p 8080:8080 mame` for a disposable instance. Finish every change with `swiftformat .`.

## Coding Style & Naming Conventions
Follow the Swift API Design Guidelines: four-space indentation, brace-on-same-line declarations, `UpperCamelCase` types, and `lowerCamelCase` identifiers. Router helpers favour `guard` for early exits and keep async closures short. Align new files with the existing directory split (application vs. mock server) and avoid introducing non-ASCII characters unless required by content. After every change set, run `swiftformat .` at the repository root so style stays consistent.

To support multiple HTTP verbs for the same path, add `#<method>` suffixes to fixture filenames (for example, `login#post.yml`). The suffix is case-insensitive and overrides the YAML `method` attribute.

## Testing Guidelines
Swift Testing (`@Suite`, `@Test`, `#expect`) is integrated alongside HummingbirdTesting clients. Keep suites under `Tests/AppTests`, mirror the target name, and reuse `TestArguments` so CLI flags stay in sync with `App.swift`. When a test needs temporary fixtures, write them into the `sample/` tree and clean them up inside the test, as demonstrated in `AppTests.swift`. Run focused checks with `swift test --filter AppTests/sampleYamlRouteServesFixture` during development.
Fixtures deleted after startup now return HTTP 404; tests should cover that behaviour when touching hot-reload logic.

## Distribution Notes

- Homebrew users can tap `osushi/mame` (formula in `Formula/mame.rb`) and run `brew install --HEAD mame` until tagged releases are available.
- Mint users can install with `mint install osushi/mame`.
- Keep these instructions updated when publishing new tags/releases.

## Commit & Pull Request Guidelines
Adopt imperative commit subjects (for example, `Refactor mock route loader`) under ~65 characters, with additional context in the body where needed. Open pull requests only after `swift test` succeeds, summarise behaviour changes, list configuration updates (new CLI flags, environment variables, YAML schema tweaks), and attach screenshots or `curl` transcripts when HTTP responses change. Document any new fixture directory structure so teammates can reproduce the same responses.

## Configuration Tips
Application logging falls back to the `LOG_LEVEL` environment variable when CLI flags are absent. When adding a CLI argument, expose it in `App.swift`, thread it through `AppArguments`, and update `TestArguments` plus any Swift Testing suites. YAML definitions should include `status`, `method`, optional `latency`, and a `json` body; validation errors are surfaced in logs with their source path.
