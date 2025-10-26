# Repository Guidelines

## Project Structure & Module Organization
The Swift package is defined in `Package.swift`. Application code lives in `Sources/App`, with `App.swift` hosting the CLI entry point and `App+build.swift` configuring the Hummingbird router and logging. Tests reside in `Tests/AppTests`, built on XCTest and HummingbirdTesting. Automated checks run from `.github/workflows/ci.yml`, and the `Dockerfile` packages the service for container deployment.

## Build, Test, and Development Commands
Run `swift build` to compile the executable and surface any compiler warnings. Use `swift run mame --hostname 0.0.0.0 --port 8080` for a local server; append `--log-level debug` as needed. Execute `swift test` before pushing; CI mirrors this command. When working in containers, `docker build -t mame .` followed by `docker run --rm -p 8080:8080 mame` launches the API.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines with 4-space indentation and braces on the same line as declarations. Use `UpperCamelCase` for types and `lowerCamelCase` for functions, variables, and route identifiers. Prefer early exits with `guard` to keep Hummingbird handlers simple. No dedicated formatter is committed; rely on `swift-format` (or Xcode’s built-in formatting) and inspect diffs to keep spacing consistent with the existing files.

## Testing Guidelines
Tests live next to the modules they cover; add new suites under `Tests/AppTests` mirroring the target name. Name test methods with intent, e.g., `testRoutesReturnGreeting`. Build isolated router tests with `HummingbirdTesting` clients like in `AppTests.swift`. Run focused suites via `swift test --filter AppTests/testApp`. Maintain coverage for any new route or middleware and include fixtures alongside tests when needed.

## Commit & Pull Request Guidelines
The exported repository snapshot omits git history, so follow standard Swift package practice: start commit subjects with an imperative verb (`Add`, `Fix`, `Refactor`) and keep them under ~65 characters, with details in the body if necessary. Open PRs only after `swift test` passes, describe behavioural changes, link issues, and document configuration updates (environment variables, ports, Docker flags). Add screenshots or curl transcripts when modifying HTTP responses.

## Configuration Tips
Runtime behaviour depends on `LOG_LEVEL`; document defaults when changing it. Expose new settings through CLI options in `App.swift` and mirror them in `TestArguments` so the test harness stays in sync.
