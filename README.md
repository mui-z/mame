# 🐈 neko

[![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge)](https://github.com/apple/swift)
[![LICENSE: MIT SUSHI-WARE🍣](https://raw.githubusercontent.com/watasuke102/mit-sushi-ware/master/MIT-SUSHI-WARE.svg)](https://github.com/mui-z/neko/blob/main/LICENSE)
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/mui_z_.svg?style=social&label=Follow%20%40mui-z)](https://twitter.com/mui_z_)


`neko` is a small Hummingbird-based HTTP service that serves JSON responses defined in filesystem YAML fixtures. The service combines static route registration at startup with dynamic file discovery for hot-reload support. Each request reloads the originating YAML, and new fixture files are discovered on demand, so editing or adding files immediately changes the returned payload—no server restart required.


## Requirements

- Swift 6.0 toolchain or newer (tested with Swift 6.2)
- macOS 14 with the Swift toolchain installed

## Installation

### Homebrew

```sh
brew tap mui-z/neko https://github.com/mui-z/neko.git
brew install neko
```

The tap consumes the formula in `Formula/neko.rb` and installs the built binary into `$(brew --prefix)/bin/neko`.

### Mint

```sh
mint install mui-z/neko
```

Mint will build the latest tagged release; pass a version (`mint install mui-z/neko@1.0.0`) to pin your toolchain.

## Running the Server

```sh
# run from repo root, pointing at the bundled fixtures
neko --hostname 0.0.0.0 --port 8080 --log-level debug --fixtures sample

# or run from inside your fixtures directory
cd sample
neko --hostname 0.0.0.0 --port 8080 --log-level debug

# or use the positional shortcut
neko sample
```

`--fixtures` (alias: `--root`, `-f`) points at the directory containing YAML files. It defaults to the current working directory, so changing into the fixture directory lets you omit the flag entirely. With the bundled fixtures (`sample/`), `GET /v1/hello` returns the contents of `sample/v1/hello.yml`.

### Command Options

```text
USAGE: neko [<fixture-directory>] [--hostname <hostname>] [--port <port>] [--log-level <log-level>] [--fixtures <fixtures>]

OPTIONS:
  -f, --fixtures, --root <fixtures>    Directory containing YAML fixtures (defaults to current dir)
  --hostname <hostname>                Hostname to bind (default: 127.0.0.1)
  --log-level <log-level>              Override logging verbosity (trace|debug|info|warning|error|critical)
  --port <port>                        Port to listen on (default: 8080)
  -h, --help                           Show help information.
```

## YAML Format

Each YAML document must contain a `body` field with the desired JSON payload. For backwards compatibility the legacy `json` field is still accepted, but new fixtures should prefer `body`. Other fields are optional and default to:

```yaml
status: 200      # optional – defaults to 200
method: GET      # optional – defaults to GET (routes are registered per method)
latency: 0       # optional – defaults to 0ms artificial delay
body:
  {
    "message": "hello world!"
  }
```

If `latency` is provided it is interpreted in milliseconds and applied on every request. Validation errors are logged with the offending file path. When a fixture file is deleted or missing at request time, the server logs the issue and returns a 404 response.

## Hot-Reload Behavior

The service provides hot-reload functionality through a hybrid approach:

1. **Static Route Registration**: At startup, all existing YAML files are registered as routes in memory for fast access
2. **Request-Time Reloading**: Each request reloads the YAML file to pick up content changes immediately
3. **Dynamic File Discovery**: When a request returns 404, the system searches the filesystem for newly added fixture files

This means:
- **Editing existing files**: Changes are reflected immediately on the next request
- **Adding new files**: Available after the first request triggers the dynamic discovery
- **Deleting files**: Returns 404 on subsequent requests

The system maintains security by normalizing file paths and preventing directory traversal attacks.

### Method-Specific Fixtures

When multiple HTTP methods target the same path, add a `#<method>` suffix to the filename. For example:

```
v1/
  multi#get.yml   # GET /v1/multi
  multi#post.yml  # POST /v1/multi
```

The HTTP method is determined by the `method` value inside each YAML file (defaulting to `GET`). The filename suffix is primarily for organization and allowing multiple methods for the same path. If the filename suffix differs from the YAML `method` field, the YAML value takes precedence and a warning is logged.

## Logging

Requests are logged through a custom middleware that prints `METHOD path -> STATUS`. Status codes are colourised when stdout/stderr is attached to a TTY; set `NO_COLOR=1` to disable colours. Errors during YAML parsing are logged once per request with the failing file path.

## Development Workflow

1. Make code changes under `Sources/App/...` or update fixtures in your fixture directory.
2. Run the formatter: `swiftformat .`
3. Execute the test suite: `swift test`

Tests (`Tests/AppTests/AppTests.swift`) use Swift Testing macros and HummingbirdTesting to verify the default route, YAML-backed responses, and hot-reload behaviour. Swift 6 currently ships its own copy of Swift Testing, so the third-party dependency emits deprecation warnings—the tests still pass, and the package can be removed when the toolchain stabilises its built-in module.

## Directory Layout

```
Sources/
  App/
    Application/         // CLI entry point and application builder
    MockServer/          // YAML parsing, validation, and router registration helpers
Tests/AppTests/          // Swift Testing suites exercising the mock server
sample/                  // Example fixtures for testing and demonstration
```

## Contributing

- Follow the structure described in `AGENTS.md`.
- Document new CLI flags or environment variables in the README when relevant.
