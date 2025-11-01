#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import HTTPTypes
import Hummingbird

struct HealthResponse: ResponseEncodable {
    let status: String
    let uptime: TimeInterval
    let version: String

    // キャッシュされた静的コンポーネント
    private nonisolated(unsafe) static let dateFormatter = ISO8601DateFormatter()
    private static let cachedHeaders: HTTPFields = {
        var headers = HTTPFields()
        headers[.contentType] = "application/json; charset=utf-8"
        return headers
    }()

    func encodeResponse(to _: Request, in _: some RequestContext) throws -> Response {
        // 動的ペイロードの構築
        let payload: [String: Any] = [
            "status": status,
            "uptime": uptime,
            "version": version,
            "timestamp": Self.dateFormatter.string(from: Date()),
        ]

        // 最適化されたJSONエンコード（prettyPrintedを削除）
        let data = try JSONSerialization.data(withJSONObject: payload)

        return Response(
            status: .ok,
            headers: Self.cachedHeaders,
            body: .init(byteBuffer: ByteBuffer(data: data)),
        )
    }
}
