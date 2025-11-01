import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import neko

@Suite struct AppTests {
    struct TestArguments: AppArguments {
        let hostname = "127.0.0.1"
        let port = 0
        let logLevel: Logger.Level? = .trace
        let fixtureDirectory: String

        init(fixtureDirectory: String = "sample") {
            self.fixtureDirectory = fixtureDirectory
        }
    }

    // MARK: - Test Helpers

    private func createTempFixtureDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neko-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func writeFixture(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeDirectory(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Log the error but don't fail the test
            print("⚠️ Failed to cleanup test directory at \(url.path): \(error.localizedDescription)")

            // Try to remove individual files if directory removal failed
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        print("⚠️ Failed to remove file \(fileURL.path): \(error.localizedDescription)")
                    }
                }

                // Try directory removal again
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    print("⚠️ Final cleanup failed for \(url.path): \(error.localizedDescription)")
                }
            }
        }
    }

    @Test
    func rootReturnsGreeting() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(String(buffer: response.body) == "Hello!")
            }
        }
    }

    @Test
    func healthEndpointReturnsSystemInfo() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")

                let responseBody = String(buffer: response.body)
                #expect(responseBody.contains("ok"))
                #expect(responseBody.contains("1.0.0"))
                #expect(responseBody.contains("uptime"))
            }
        }
    }

    @Test
    func sampleYamlRouteServesFixture() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/hello", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")
                #expect(String(buffer: response.body) == "{\"message\":\"hello world!\"}")
            }
        }
    }

    @Test
    func hotReloadReflectsUpdatedYaml() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hot_reload.yml")

        let initialYAML = """
        status: 200
        method: GET
        body:
          {"message":"original"}
        """
        let updatedYAML = """
        status: 201
        method: GET
        body:
          {"message":"updated"}
        """

        try writeFixture(initialYAML, to: fileURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))
        try await app.test(.router) { client in
            try await client.execute(uri: "/hot_reload", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "{\"message\":\"original\"}")
            }

            try writeFixture(updatedYAML, to: fileURL)

            try await client.execute(uri: "/hot_reload", method: .get) { response in
                #expect(response.status == .created)
                #expect(String(buffer: response.body) == "{\"message\":\"updated\"}")
            }
        }
    }

    @Test
    func newlyAddedFixtureServesWithoutRestart() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("late_binding.yml")
        let yaml = """
        status: 202
        method: GET
        body:
          {"message":"late"}
        """

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))

        try await app.test(.router) { client in
            try writeFixture(yaml, to: fileURL)
            try await client.execute(uri: "/late_binding", method: .get) { response in
                #expect(response.status == .accepted)
                #expect(String(buffer: response.body) == "{\"message\":\"late\"}")
            }
        }
    }

    @Test
    func newlyAddedMethodSpecificFixtureHonoursOverride() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("late_binding#post.yml")
        let yaml = """
        status: 201
        body:
          {"message":"late post"}
        """

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))

        try await app.test(.router) { client in
            try writeFixture(yaml, to: fileURL)

            try await client.execute(uri: "/late_binding", method: .post) { response in
                #expect(response.status == .created)
                #expect(String(buffer: response.body) == "{\"message\":\"late post\"}")
            }
        }
    }

    @Test
    func missingFixtureReturnsNotFound() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("ephemeral.yml")
        let yaml = """
        body:
          {"message":"temp"}
        """
        try writeFixture(yaml, to: fileURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))

        try FileManager.default.removeItem(at: fileURL)

        try await app.test(.router) { client in
            try await client.execute(uri: "/ephemeral", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test
    func fileNameSuffixOverridesMethod() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let getURL = tempDir.appendingPathComponent("multi#get.yml")
        let postURL = tempDir.appendingPathComponent("multi#post.yml")
        let getYAML = """
        body:
          {"message":"get variant"}
        """
        let postYAML = """
        body:
          {"message":"post variant"}
        """
        try writeFixture(getYAML, to: getURL)
        try writeFixture(postYAML, to: postURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))
        try await app.test(.router) { client in
            try await client.execute(uri: "/multi", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "{\"message\":\"get variant\"}")
            }

            try await client.execute(uri: "/multi", method: .post) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "{\"message\":\"post variant\"}")
            }
        }
    }

    // MARK: - Edge Case Tests

    @Test
    func invalidYAMLReturnsError() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("invalid.yml")
        let invalidYAML = """
        invalid: yaml: content:
          - missing
        proper: structure
        """

        try writeFixture(invalidYAML, to: fileURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))
        try await app.test(.router) { client in
            try await client.execute(uri: "/invalid", method: .get) { response in
                #expect(response.status == .internalServerError)
            }
        }
    }

    @Test
    func unicodeContentHandling() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("unicode.yml")
        let unicodeYAML = """
        status: 200
        method: GET
        body:
          {"message": "こんにちは世界 🌍", "emoji": "😺🐱"}
        """

        try writeFixture(unicodeYAML, to: fileURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))
        try await app.test(.router) { client in
            try await client.execute(uri: "/unicode", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")
                let responseBody = String(buffer: response.body)
                #expect(responseBody.contains("こんにちは世界"))
                #expect(responseBody.contains("😺"))
            }
        }
    }

    @Test
    func emptyYAMLFileReturnsError() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty.yml")
        try writeFixture("", to: fileURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))
        try await app.test(.router) { client in
            try await client.execute(uri: "/empty", method: .get) { response in
                #expect(response.status == .internalServerError)
            }
        }
    }

    @Test
    func malformedJSONInBodyReturnsError() async throws {
        let tempDir = try createTempFixtureDirectory()
        defer { removeDirectory(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("malformed.yml")
        let malformedYAML = """
        status: 200
        method: GET
        body:
          {"message": "unclosed json
        """

        try writeFixture(malformedYAML, to: fileURL)

        let app = try await buildApplication(TestArguments(fixtureDirectory: tempDir.path))
        try await app.test(.router) { client in
            try await client.execute(uri: "/malformed", method: .get) { response in
                #expect(response.status == .internalServerError)
            }
        }
    }
}
