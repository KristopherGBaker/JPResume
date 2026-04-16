import Testing
@testable import jpresume
import Foundation

@Suite("Config Manager")
struct ConfigTests {
    @Test func loadSampleConfig() throws {
        let url = Bundle.module.url(forResource: "sample_config", withExtension: "yaml", subdirectory: "Fixtures")!
        let config = try ConfigManager.load(from: url)
        #expect(config != nil)
        #expect(config?.nameKanji == "ドウ ジェーン")
        #expect(config?.addressCurrent.prefecture == "東京都")
        #expect(config?.spouse == false)
        #expect(config?.phone == "+81-80-9999-0000")
    }

    @Test func loadMissingConfig() throws {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_jpresume_config.yaml")
        let config = try ConfigManager.load(from: url)
        #expect(config == nil)
    }

    @Test func saveAndLoadRoundtrip() throws {
        let config = JapanConfig(
            nameKanji: "テスト太郎",
            nameFurigana: "テストタロウ",
            addressCurrent: JapaneseAddress(
                postalCode: "100-0001",
                prefecture: "東京都",
                city: "千代田区"
            ),
            phone: "090-0000-0000"
        )

        let tmpPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jpresume_test_config_\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: tmpPath) }

        try ConfigManager.save(config, to: tmpPath)
        let loaded = try ConfigManager.load(from: tmpPath)

        #expect(loaded?.nameKanji == "テスト太郎")
        #expect(loaded?.addressCurrent.prefecture == "東京都")
    }
}
