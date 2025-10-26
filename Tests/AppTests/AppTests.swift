import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import XCTest

@testable import mame

final class AppTests: XCTestCase {
    struct TestArguments: AppArguments {
        let hostname = "127.0.0.1"
        let port = 0
        let logLevel: Logger.Level? = .trace
    }

    func testApp() async throws {
        let args = TestArguments()
        let app = try await buildApplication(args)
        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                XCTAssertEqual(response.body, ByteBuffer(string: "Hello!"))
            }
        }
    }

    func testSampleYamlRoute() async throws {
        let app = try await buildApplication(TestArguments())
        try await app.test(.router) { client in
            try await client.execute(uri: "/sample/v1/hello", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "application/json; charset=utf-8")
                XCTAssertEqual(String(buffer: response.body), "{\"message\":\"hello world!\"}")
            }
        }
    }
}
