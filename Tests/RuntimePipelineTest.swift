import Foundation

@main
struct RuntimePipelineTest {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            fputs("Usage: RuntimePipelineTest <path-to-IntentZeroDebugService.zip>\n", stderr)
            exit(2)
        }
        let zipPath = CommandLine.arguments[1]
        let fm = FileManager.default
        guard fm.fileExists(atPath: zipPath) else {
            fputs("Provided zip path does not exist: \(zipPath)\n", stderr)
            exit(2)
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("IntentZeroDebugPipelineTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let pipeline = IntentPipeline(resourceZipURL: URL(fileURLWithPath: zipPath),
                                      overrideSupportRoot: tempRoot)
        let idea = "포모도로 타이머 핵심 기능 3가지"
        let detection = try pipeline.detectDomain(for: idea)
        guard !detection.domain.isEmpty else {
            fputs("Detection failed: empty domain\n", stderr)
            exit(1)
        }

        let session = try pipeline.startInterview(for: detection)
        guard session.questions.isEmpty == false else {
            fputs("Interview start failed: no questions loaded\n", stderr)
            exit(1)
        }

        print("Runtime pipeline test passed. Domain=\(detection.domain), questions=\(session.questions.count)")
    }
}
