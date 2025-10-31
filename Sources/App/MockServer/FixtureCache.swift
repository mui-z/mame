#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import HTTPTypes
import Hummingbird
import Logging

actor FixtureCache {
    private var cache: [URL: CachedFixture] = [:]
    private let logger: Logger
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    struct CachedFixture {
        let definition: MockRouteDefinition
        let modifiedTime: Date
        let checksum: String
    }
    
    func getFixture(for url: URL) async throws -> MockRouteDefinition? {
        let fileManager = FileManager.default
        
        // ファイルの存在確認
        guard fileManager.fileExists(atPath: url.path) else {
            cache.removeValue(forKey: url)
            return nil
        }
        
        // ファイルの属性取得
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let currentModifiedTime = attributes[.modificationDate] as? Date ?? Date.distantPast
        let currentChecksum = try? calculateSimpleChecksum(for: url)
        
        // キャッシュチェック
        if let cached = cache[url] {
            if cached.modifiedTime == currentModifiedTime && 
               cached.checksum == currentChecksum {
                logger.debug("Using cached fixture", metadata: ["file": "\(url.path)"])
                return cached.definition
            }
        }
        
        // キャッシュミス - ファイルから読み込み
        logger.debug("Loading fixture from disk", metadata: ["file": "\(url.path)"])
        let definition = try MockRouteLoader.loadDefinition(from: url)
        
        // キャッシュに保存
        let cachedFixture = CachedFixture(
            definition: definition,
            modifiedTime: currentModifiedTime,
            checksum: currentChecksum ?? ""
        )
        cache[url] = cachedFixture
        
        return definition
    }
    
    func invalidate(url: URL) {
        cache.removeValue(forKey: url)
        logger.debug("Invalidated cache", metadata: ["file": "\(url.path)"])
    }
    
    func clearAll() {
        let count = cache.count
        cache.removeAll()
        logger.debug("Cleared all cached fixtures", metadata: ["count": "\(count)"])
    }
    
    private func calculateSimpleChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(data.hashValue)
    }
}
