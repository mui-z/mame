#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif
import Dispatch
import Logging

actor FixtureWatcher {
    private let directoryURL: URL
    private let logger: Logger
    private let fixtureCache: FixtureCache
    private var fileWatcher: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "neko.fixture-watcher")

    init(directoryURL: URL, fixtureCache: FixtureCache, logger: Logger) {
        self.directoryURL = directoryURL
        self.fixtureCache = fixtureCache
        self.logger = logger
    }

    func startWatching() {
        guard fileWatcher == nil else {
            logger.warning("File watcher already started")
            return
        }

        // ディレクトリの存在確認
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            logger.warning("Cannot watch non-existent directory", metadata: ["directory": "\(directoryURL.path)"])
            return
        }

        // ファイルシステム監視のセットアップ
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            logger.error("Failed to open directory for watching", metadata: ["directory": "\(directoryURL.path)"])
            return
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue,
        )

        // イベントハンドラの設定
        fileWatcher?.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.handleFileSystemEvent()
            }
        }

        // キャンセルハンドラ
        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }

        fileWatcher?.resume()
        logger.info("Started watching fixture directory", metadata: ["directory": "\(directoryURL.path)"])
    }

    func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        logger.info("Stopped watching fixture directory", metadata: ["directory": "\(directoryURL.path)"])
    }

    nonisolated func cleanup() {
        // Note: fileWatcher cleanup is handled in stopWatching()
        // This method exists for explicit cleanup when needed
    }

    private func handleFileSystemEvent() {
        logger.debug("File system event detected", metadata: ["directory": "\(directoryURL.path)"])

        // 変更されたYAMLファイルを検出してキャッシュを無効化
        Task {
            await invalidateChangedFixtures()
        }
    }

    private func invalidateChangedFixtures() async {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else {
            return
        }

        var invalidatedCount = 0
        let urls = enumerator.compactMap { $0 as? URL }

        for fileURL in urls {
            let standardizedURL = fileURL.standardizedFileURL
            let fileExtension = standardizedURL.pathExtension.lowercased()

            guard fileExtension == "yml" || fileExtension == "yaml" else { continue }

            do {
                let attributes = try fileManager.attributesOfItem(atPath: standardizedURL.path)
                let modifiedTime = attributes[.modificationDate] as? Date ?? Date.distantPast

                // キャッシュをチェックして古い場合は無効化
                // 注: ここではシンプルに全てのYAMLファイルを無効化
                // より高度な実装では変更時刻を比較して無効化を判断
                await fixtureCache.invalidate(url: standardizedURL)
                invalidatedCount += 1

                logger.debug("Invalidated fixture cache", metadata: [
                    "file": "\(standardizedURL.path)",
                    "modified": "\(modifiedTime)",
                ])

            } catch {
                logger.warning("Failed to process file during invalidation", metadata: [
                    "file": "\(standardizedURL.path)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        if invalidatedCount > 0 {
            logger.info("Invalidated fixture caches", metadata: ["count": "\(invalidatedCount)"])
        }
    }
}
