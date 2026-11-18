import Foundation

/// Compile with the app's actual protocol model file; no copied wire schema or simulator.
@main
struct DecodeRulesEvents {
    private struct Envelope: Decodable { let type: String }

    static func main() {
        let paths = Array(CommandLine.arguments.dropFirst())
        guard !paths.isEmpty else {
            FileHandle.standardError.write(Data("Usage: decode-events.sh /absolute/path/to/events.jsonl [...]\n".utf8))
            exit(64)
        }
        let decoder = JSONDecoder()
        var failures = 0
        var total = 0
        for path in paths {
            let contents: String
            do { contents = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) }
            catch {
                failures += 1
                FileHandle.standardError.write(Data("\(path): \(error.localizedDescription)\n".utf8))
                continue
            }
            var snapshots = 0
            var prompts = 0
            for (offset, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let data = Data(line.utf8)
                do {
                    switch try decoder.decode(Envelope.self, from: data).type {
                    case "snapshot":
                        _ = try decoder.decode(RulesSnapshot.self, from: data)
                        snapshots += 1
                    case "prompt":
                        _ = try decoder.decode(RulesPrompt.self, from: data)
                        prompts += 1
                    default: break
                    }
                } catch {
                    failures += 1
                    FileHandle.standardError.write(Data("\(path):\(offset + 1): \(describe(error))\n".utf8))
                }
            }
            if snapshots == 0 || prompts == 0 {
                failures += 1
                FileHandle.standardError.write(Data("\(path): expected both captured snapshots and prompts\n".utf8))
            }
            total += snapshots + prompts
            print("\(path): \(snapshots) snapshots, \(prompts) prompts decoded")
        }
        print("\(failures == 0 ? "PASS" : "FAIL"): \(total) events decoded with the app's Swift models; \(failures) failures")
        if failures != 0 { exit(1) }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "Missing \((context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: "."))"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context), DecodingError.dataCorrupted(let context):
            return "\(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        default: return error.localizedDescription
        }
    }
}
