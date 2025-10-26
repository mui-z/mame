# 🫛mame

[![Swift](https://img.shields.io/badge/lang/swift)](https://github.com/apple/swift)
[![LICENSE: MIT SUSHI-WARE🍣](https://raw.githubusercontent.com/watasuke102/mit-sushi-ware/master/MIT-SUSHI-WARE.svg)](https://github.com/mui-z/mame/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/mui-z/mame)](https://gitHub.com/mui-z/mame/stargazers/)

`mame` is a small Hummingbird-based HTTP service that serves JSON responses defined in filesystem YAML fixtures. Each request reloads the originating YAML, so editing files under `sample/` immediately changes the returned payload—no server restart required.


## Requirements

- Swift 6.0 toolchain or newer (tested with Swift 6.2)
- macOS 14 / Linux with Swift toolchain installed

## Installation

### Homebrew

```sh
brew tap mui-z/mame https://github.com/mui-z/mame.git
brew install --HEAD mame
```

The tap consumes the formula in `Formula/mame.rb` and installs the built binary into `$(brew --prefix)/bin/mame`. Replace `--HEAD` with a tagged release once stable tarballs are published.

### Mint

```sh
mint install mui-z/mame
```

Mint will build the latest tagged release; pass a version (`mint install mui-z/mame@0.1.0`) to pin your toolchain.

## Running the Server

```sh
swift build
# run from repo root, pointing at the bundled fixtures
swift run mame --hostname 0.0.0.0 --port 8080 --log-level debug --fixtures sample

# or run from inside your fixtures directory
cd sample
swift run mame --hostname 0.0.0.0 --port 8080 --log-level debug

# or use the positional shortcut
swift run mame sample
```

`--fixtures` (alias: `--root`, `-f`) points at the directory containing YAML files. It defaults to the current working directory, so changing into the fixture directory lets you omit the flag entirely. With the bundled fixtures (`sample/`), `GET /v1/hello` returns the contents of `sample/v1/hello.yml`.

### Command Options

```text
USAGE: mame [<fixture-directory>] [--hostname <hostname>] [--port <port>] [--log-level <log-level>] [--fixtures <fixtures>]

OPTIONS:
  -f, --fixtures, --root <fixtures>    Directory containing YAML fixtures (defaults to current dir)
  --hostname <hostname>                Hostname to bind (default: 127.0.0.1)
  --log-level <log-level>              Override logging verbosity (trace|debug|info|warning|error|critical)
  --port <port>                        Port to listen on (default: 8080)
  -h, --help                           Show help information.
```

## YAML Format

Each YAML document must contain a `json` field with a JSON object/body. Other fields are optional and default to:

```yaml
status: 200      # optional – defaults to 200
method: GET      # optional – defaults to GET (routes are registered per method)
latency: 0       # optional – defaults to 0ms artificial delay
json:
  {
    "message": "hello world!"
  }
```

If `latency` is provided it is interpreted in milliseconds and applied on every request. Validation errors are logged with the offending file path. When a fixture file is deleted or missing at request time, the server logs the issue and returns a 404 response.

### Method-Specific Fixtures

When multiple HTTP methods target the same path, add a `#<method>` suffix to the filename. For example:

```
v1/
  multi#get.yml   # GET /v1/multi
  multi#post.yml  # POST /v1/multi
```

The suffix is case-insensitive and overrides the YAML `method` field when present. Files without the suffix continue to rely on the `method` value (defaulting to `GET`).

## Logging

Requests are logged through a custom middleware that prints `METHOD path -> STATUS`. Status codes are colourised when stdout/stderr is attached to a TTY; set `NO_COLOR=1` to disable colours. Errors during YAML parsing are logged once per request with the failing file path.

## Development Workflow

1. Make code changes under `Sources/App/...` or update fixtures in `sample/`.
2. Run the formatter: `swiftformat .`
3. Execute the test suite: `swift test`

Tests (`Tests/AppTests/AppTests.swift`) use Swift Testing macros and HummingbirdTesting to verify the default route, YAML-backed responses, and hot-reload behaviour. Swift 6 currently ships its own copy of Swift Testing, so the third-party dependency emits deprecation warnings—the tests still pass, and the package can be removed when the toolchain stabilises its built-in module.

## Container Usage

```sh
docker build -t mame .
docker run --rm -p 8080:8080 mame
```

## Directory Layout

```
Sources/
  App/
    Application/         // CLI entry point and application builder
    MockServer/          // YAML parsing, validation, and router registration helpers
sample/                  // Hierarchical mock responses (eg. sample/v1/hello.yml)
Tests/AppTests/          // Swift Testing suites exercising the mock server
```

## Contributing

- Follow the structure described in `AGENTS.md`.
- Keep commit subjects in imperative mood (e.g. `Add orders mock route`).
- Document new CLI flags or environment variables in the README when relevant.
