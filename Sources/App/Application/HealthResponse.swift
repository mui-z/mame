import Foundation
import HTTPTypes
import Hummingbird

struct HealthResponse: ResponseEncodable {
    let status: String
    let uptime: TimeInterval
    let version: String

    func encodeResponse(to _: Request, in _: some RequestContext) throws -> Response {
        let payload: [String: Any] = [
            "status": status,
            "uptime": uptime,
            "version": version,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw HTTPError(.internalServerError)
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/json; charset=utf-8"

        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(string: string)),
        )
    }
}
