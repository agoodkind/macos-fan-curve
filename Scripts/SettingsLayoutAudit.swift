#!/usr/bin/env swift

import Foundation

struct Violation {
    let file: String
    let line: Int
    let message: String

    var description: String {
        "\(file):\(line): \(message)"
    }
}

let root = CommandLine.arguments.dropFirst().first ?? "Sources/Views"
let fileManager = FileManager.default
let auditedNonSettingsFileNames: Set<String> = [
    "AboutContentView.swift",
    "LoadAssistModuleView.swift",
]

guard var isDirectory = Optional(ObjCBool(false)),
    fileManager.fileExists(atPath: root, isDirectory: &isDirectory),
    isDirectory.boolValue
else {
    FileHandle.standardError.write(
        Data("settings-layout-audit failed: source root not found: \(root)\n".utf8)
    )
    exit(1)
}

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
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        guard fileName.contains("Settings") || auditedNonSettingsFileNames.contains(fileName) else {
            return nil
        }
        return "\(root)/\(path)"
    }.sorted()
}

func scanBlock(lines: [String], startIndex: Int) -> (endIndex: Int, hasSpacer: Bool, isAllowed: Bool) {
    var cursor = startIndex
    var depth = 0
    var hasOpened = false
    var hasSpacer = false
    var isAllowed = false

    while cursor < lines.count {
        let line = lines[cursor]
        if line.contains("settings-layout-audit: allow hstack-spacer") {
            isAllowed = true
        }
        if matches(line, #"Spacer\s*\("#) {
            hasSpacer = true
        }

        let openCount = count("{", in: line)
        let closeCount = count("}", in: line)
        if openCount > 0 { hasOpened = true }
        depth += openCount - closeCount

        if hasOpened, depth <= 0 {
            return (cursor, hasSpacer, isAllowed)
        }
        cursor += 1
    }

    return (lines.count - 1, hasSpacer, isAllowed)
}

var violations: [Violation] = []

for file in swiftFiles(at: root) {
    let contents = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let fileName = URL(fileURLWithPath: file).lastPathComponent
    let isSettingsComponents = fileName == "SettingsFormComponents.swift"

    if contents.contains("SettingsResponsiveRow") {
        violations.append(
            Violation(
                file: file,
                line: 1,
                message: "use focused settings row primitives instead of SettingsResponsiveRow"
            )
        )
    }

    if isSettingsComponents,
        let sliderRange = contents.range(of: "struct SettingsSliderRow"),
        let toggleRange = contents.range(of: "struct SettingsToggleDescriptionRow"),
        sliderRange.lowerBound < toggleRange.lowerBound
    {
        let sliderBlock = String(contents[sliderRange.lowerBound..<toggleRange.lowerBound])
        if sliderBlock.contains("SettingsAccessoryRow") {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "SettingsSliderRow must use a dedicated full-row slider layout"
                )
            )
        }
    }

    if fileName == "AdvancedSettingsView.swift",
        contents.contains(#""Expanded Range""#),
        (!contents.contains(#"Text("Fan Range Limits")"#) || !contents.contains("SettingsDangerDisclosure"))
    {
        violations.append(
            Violation(
                file: file,
                line: 1,
                message: "Expanded Range must live under the Fan Range Limits disclosure"
            )
        )
    }

    var index = 0
    while index < lines.count {
        let line = lines[index]
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("//") {
            index += 1
            continue
        }

        if matches(line, #"LabeledContent\s*\("#) {
            violations.append(
                Violation(
                    file: file,
                    line: index + 1,
                    message: "use focused settings row primitives instead of direct LabeledContent"
                )
            )
        }

        if matches(line, #"Slider\s*\("#), !isSettingsComponents {
            violations.append(
                Violation(
                    file: file,
                    line: index + 1,
                    message: "use SettingsSliderRow instead of direct Slider in settings panes"
                )
            )
        }

        if matches(line, #"HStack\s*\("#) {
            let block = scanBlock(lines: lines, startIndex: index)
            if block.hasSpacer, !block.isAllowed {
                violations.append(
                    Violation(
                        file: file,
                        line: index + 1,
                        message: "use SettingsAccessoryRow or add a reviewed settings-layout-audit allowance before HStack with Spacer"
                    )
                )
            }
            index = block.endIndex + 1
            continue
        }

        index += 1
    }
}

if violations.isEmpty {
    print("settings-layout-audit: ok")
} else {
    for violation in violations {
        FileHandle.standardError.write(Data((violation.description + "\n").utf8))
    }
    FileHandle.standardError.write(
        Data("settings-layout-audit failed: \(violations.count) violation(s)\n".utf8)
    )
    exit(1)
}
