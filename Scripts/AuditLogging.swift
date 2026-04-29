#!/usr/bin/env swift

import Foundation

struct Violation {
    let file: String
    let line: Int?
    let message: String

    var description: String {
        if let line {
            return "\(file):\(line): \(message)"
        }
        return "\(file): \(message)"
    }
}

let root = CommandLine.arguments.dropFirst().first ?? "Sources"
let fileManager = FileManager.default

guard var isDirectory = Optional(ObjCBool(false)),
    fileManager.fileExists(atPath: root, isDirectory: &isDirectory),
    isDirectory.boolValue
else {
    FileHandle.standardError.write(Data("log-audit failed: source root not found: \(root)\n".utf8))
    exit(1)
}

let rawLoggingPattern = #"(^|[^A-Za-z_])(print|NSLog|os_log)\(|Logger\(label:|Logger\(subsystem:"#
let boundaryPattern =
    #"(^|[^A-Za-z0-9_])(catch|try[?!]?|FileManager|UserDefaults|SMAppService|NotificationCenter|CFNotificationCenter|NSWorkspace|Task\s*\{|ProcessInfo|Data\(contentsOf:|JSONEncoder|JSONDecoder|write\(to:|write\(contentsOf:|readAndApply|createDirectory|removeItem|copyItem|moveItem|open\()"#
let categoryPattern = #"AppLog\.(make|signposter)\(category:\s*"[^"]+""#
let catchPattern = #"(^|[^A-Za-z0-9_])catch(\s|\{|$)"#
let logPattern = #"(^|[^A-Za-z0-9_])(log|[A-Za-z_][A-Za-z0-9_]*Log|frameLog|exitLog)\.(error|warning|notice|info|debug)\("#
let sideEffectTryPattern =
    #"(set[A-Za-z0-9_]*\(|write[A-Za-z0-9_]*\(|remove[A-Za-z0-9_]*\(|move[A-Za-z0-9_]*\(|create[A-Za-z0-9_]*\(|open\(|Data\(contentsOf:|JSONEncoder|JSONDecoder|readAndApply|getFanInfo|readKey|setFanRPM|setFanAuto)"#

func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}

func count(_ character: Character, in line: String) -> Int {
    line.reduce(0) { $1 == character ? $0 + 1 : $0 }
}

func swiftFiles(at root: String) -> [String] {
    guard let enumerator = fileManager.enumerator(atPath: root) else { return [] }
    return enumerator.compactMap { entry -> String? in
        guard let path = entry as? String, path.hasSuffix(".swift") else { return nil }
        return "\(root)/\(path)"
    }.sorted()
}

var violations: [Violation] = []

for file in swiftFiles(at: root) {
    let contents = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let codeLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    let code = codeLines.joined(separator: "\n")

    for (index, line) in lines.enumerated() {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
        guard matches(line, rawLoggingPattern) else { continue }
        guard !line.contains("CLIOut.print"), !line.contains("CLIOut.err") else { continue }
        violations.append(
            Violation(file: file, line: index + 1, message: "use AppLog instead of print(), NSLog, os_log, or direct Logger construction")
        )
    }

    if matches(code, boundaryPattern) {
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "import AppLog" }) {
            violations.append(Violation(file: file, line: nil, message: "boundary code must import AppLog"))
        }
        if !matches(code, categoryPattern) {
            violations.append(
                Violation(file: file, line: nil, message: "boundary code must declare an AppLog category with AppLog.make/signposter(category:)")
            )
        }
    }

    for index in lines.indices where matches(lines[index], catchPattern) {
        var depth = count("{", in: lines[index]) - count("}", in: lines[index])
        var seenOpen = depth > 0
        var logged = matches(lines[index], logPattern)
        var cursor = index + 1

        while cursor < lines.count, cursor <= index + 80, !seenOpen || depth > 0 {
            let line = lines[cursor]
            logged = logged || matches(line, logPattern)
            let opens = count("{", in: line)
            let closes = count("}", in: line)
            if opens > 0 { seenOpen = true }
            depth += opens - closes
            cursor += 1
        }

        if !logged {
            violations.append(
                Violation(
                    file: file,
                    line: index + 1,
                    message: "catch block must log failure context and recovery decision through AppLog"
                )
            )
        }
    }

    for (index, line) in lines.enumerated() where line.contains("try?") {
        if line.contains("logging-audit: allow-silent-try") { continue }
        if matches(line, sideEffectTryPattern) {
            violations.append(
                Violation(
                    file: file,
                    line: index + 1,
                    message: "side-effecting try? must log the failure path or add // logging-audit: allow-silent-try with a reason"
                )
            )
        }
    }
}

if violations.isEmpty {
    print("log-audit: ok")
} else {
    for violation in violations {
        FileHandle.standardError.write(Data((violation.description + "\n").utf8))
    }
    FileHandle.standardError.write(Data("log-audit failed: \(violations.count) violation(s)\n".utf8))
    exit(1)
}
