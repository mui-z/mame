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
        let fixtureDirectory = "sample"
    }

    @Test
    func rootReturnsGreeting() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.body == ByteBuffer(string: "Hello!"))
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
        let fileManager = FileManager.default
        let baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("sample")
            .appendingPathComponent("v1")
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let fileURL = baseURL.appendingPathComponent("hot_reload.yml")

        let initialYAML = """
        status: 200
        method: GET
        json:
          {"message":"original"}
        """
        let updatedYAML = """
        status: 201
        method: GET
        json:
          {"message":"updated"}
        """

        try initialYAML.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: fileURL) }

        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/hot_reload", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "{\"message\":\"original\"}")
            }

            try updatedYAML.write(to: fileURL, atomically: true, encoding: .utf8)

            try await client.execute(uri: "/v1/hot_reload", method: .get) { response in
                #expect(response.status == .created)
                #expect(String(buffer: response.body) == "{\"message\":\"updated\"}")
            }
        }
    }

    @Test
    func missingFixtureReturnsNotFound() async throws {
        let fileManager = FileManager.default
        let baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("sample")
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let fileURL = baseURL.appendingPathComponent("ephemeral.yml")
        let yaml = """
        json:
          {"message":"temp"}
        """
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)

        defer { try? fileManager.removeItem(at: fileURL) }

        let app = try await buildApplication(TestArguments())

        try fileManager.removeItem(at: fileURL)

        try await app.test(.router) { client in
            try await client.execute(uri: "/ephemeral", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test
    func fileNameSuffixOverridesMethod() async throws {
        let fileManager = FileManager.default
        let baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("sample")
            .appendingPathComponent("v1")
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let getURL = baseURL.appendingPathComponent("multi#get.yml")
        let postURL = baseURL.appendingPathComponent("multi#post.yml")
        let getYAML = """
        json:
          {"message":"get variant"}
        """
        let postYAML = """
        json:
          {"message":"post variant"}
        """
        try getYAML.write(to: getURL, atomically: true, encoding: .utf8)
        try postYAML.write(to: postURL, atomically: true, encoding: .utf8)
        defer {
            try? fileManager.removeItem(at: getURL)
            try? fileManager.removeItem(at: postURL)
        }

        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/multi", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "{\"message\":\"get variant\"}")
            }

            try await client.execute(uri: "/v1/multi", method: .post) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "{\"message\":\"post variant\"}")
            }
        }
    }
}
