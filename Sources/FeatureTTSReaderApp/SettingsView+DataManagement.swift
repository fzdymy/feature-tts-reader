import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {

    func exportData() {
        let docs = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let exportURL = docs.appendingPathComponent("tts-reader-backup-\(Date().timeIntervalSince1970).json")

        do {
            let state = ReaderState(
                bookText: store.bookText,
                chapters: store.chapters,
                characters: store.characters,
                scriptSegments: store.scriptSegments,
                selectedChapterID: store.selectedChapterID,
                books: store.books,
                currentBookTitle: store.currentBookTitle,
                currentBookID: store.currentBookID,
                currentBookProgress: store.currentBookProgress,
                readerFontSize: store.readerFontSize,
                readerLineSpacing: store.readerLineSpacing,
                readerTheme: store.readerTheme,
                defaultVoice: store.characters.first?.voiceID ?? "",
                defaultRate: store.defaultRate,
                defaultPitch: store.defaultPitch,
                defaultStyle: store.defaultStyle,
                bookmarks: store.bookmarks,
                bookProgressByChapter: store.bookProgressByChapter,
                lastReadChapterIndexByBook: store.lastReadChapterIndexByBook,
                defaultSensitivity: store.defaultSensitivity,
                lastScannedBookText: store.lastScannedBookText,
                playTimeoutSeconds: store.playTimeoutSeconds,
                readerFontName: store.readerFontName,
                readerParagraphSpacing: store.readerParagraphSpacing,
                customBackgroundImage: store.customBackgroundImage,
                showChapterTitle: store.showChapterTitle,
                showProgressBar: store.showProgressBar,
                showPageNumber: store.showPageNumber,
                showTime: store.showTime,
                showBattery: store.showBattery,
                showBookCover: store.showBookCover,
                showReadingProgress: store.showReadingProgress,
                ttsQueue: store.ttsQueue,
                ttsCurrentIndex: store.ttsCurrentIndex,
                ttsIsPlaying: store.ttsIsPlaying,
                ttsChapterTitle: store.ttsChapterTitle,
                ttsSegmentTitle: store.ttsSegmentTitle,
                recommendations: store.recommendations,
                statusMessage: store.statusMessage,
                isBusy: store.isBusy,
                currentPlayingLine: store.currentPlayingLine,
                playProgress: store.playProgress,
                isSpeaking: store.isSpeaking
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: exportURL, options: Data.WritingOptions.atomic)

            let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Export failed: \(error)")
        }
    }

    func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                let state = try JSONDecoder().decode(ReaderState.self, from: data)
                store.restoreState(state)
                store.statusMessage = "数据导入成功。"
            } catch {
                store.statusMessage = "导入失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            store.statusMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func resetToDefaults() {
        store.clearLibrary()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }

    func loadAppSettings() {
        selectedAppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "system") ?? .system
        selectedBookshelfLayout = BookshelfLayout(rawValue: UserDefaults.standard.string(forKey: "bookshelfLayout") ?? "grid") ?? .grid
        enableHaptics = UserDefaults.standard.object(forKey: "enableHaptics") as? Bool ?? true
        autoSaveInterval = UserDefaults.standard.object(forKey: "autoSaveInterval") as? Double ?? 30
        maxCacheSize = UserDefaults.standard.object(forKey: "maxCacheSize") as? Double ?? 500
    }

    func saveAppSettings() {
        UserDefaults.standard.set(selectedAppTheme.rawValue, forKey: "appTheme")
        UserDefaults.standard.set(selectedBookshelfLayout.rawValue, forKey: "bookshelfLayout")
        UserDefaults.standard.set(enableHaptics, forKey: "enableHaptics")
        UserDefaults.standard.set(autoSaveInterval, forKey: "autoSaveInterval")
        UserDefaults.standard.set(maxCacheSize, forKey: "maxCacheSize")
    }

    func applyAppTheme(_ theme: AppTheme) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                switch theme {
                case .system:
                    window.overrideUserInterfaceStyle = .unspecified
                case .light:
                    window.overrideUserInterfaceStyle = .light
                case .dark:
                    window.overrideUserInterfaceStyle = .dark
                }
            }
        }
    }

    func calculateCacheSize() async {
        let urls = [
            FileManager.default.temporaryDirectory,
            (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        ]
        var totalSize: Int64 = 0
        for url in urls {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let size = attrs.fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        await MainActor.run {
            cacheSize = formatter.string(fromByteCount: totalSize)
        }
    }

    func clearCache() {
        let urls = [
            FileManager.default.temporaryDirectory,
            (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        ]
        for url in urls {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
        Task { await calculateCacheSize() }
    }
}
