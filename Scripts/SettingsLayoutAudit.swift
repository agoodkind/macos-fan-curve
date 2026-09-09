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

func sourceBlock(in contents: String, from startMarker: String, to endMarker: String) -> String? {
    guard let startRange = contents.range(of: startMarker),
        let endRange = contents[startRange.upperBound...].range(of: endMarker)
    else {
        return nil
    }

    return String(contents[startRange.lowerBound..<endRange.lowerBound])
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
    let isSliderRowFile = fileName == "SettingsSliderRow.swift"

    if contents.contains("SettingsResponsiveRow") {
        violations.append(
            Violation(
                file: file,
                line: 1,
                message: "use focused settings row primitives instead of SettingsResponsiveRow"
            )
        )
    }

    if isSliderRowFile,
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

        if !sliderBlock.contains("private var sliderControl: some View")
            || !sliderBlock.contains("SettingsFullWidthSlider(")
            || !sliderBlock.contains(".frame(height: SettingsFormComponents.sliderControlHeight)")
        {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "SettingsSliderRow slider control must use the full-width slider bridge"
                )
            )
        }

        if !contents.contains("struct SettingsFullWidthSlider: NSViewRepresentable") {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "SettingsSliderRow requires the full-width AppKit slider bridge"
                )
            )
        }
    }

    if isSettingsComponents {
        if !contents.contains("struct SettingsAnimatedDisclosure<Label: View, Content: View>: View")
            || !contents.contains("disclosureChevronWidth")
            || !contents.contains("disclosureTitleSpacing")
            || !contents.contains("disclosureContentLeadingPadding")
            || !contents.contains("withAnimation(SettingsFormComponents.disclosureAnimation)")
            || !contents.contains(".contentShape(Rectangle())")
            || !contents.contains("transaction.animation = nil")
            || !contents.contains(".opacity(contentIsVisible ? 1 : 0)")
            || !contents.contains("disclosureContentCollapseOffset")
            || !contents.contains("readSettingsDisclosureContentHeight")
            || !contents.contains("struct SettingsDisclosureHeightKey: PreferenceKey")
            || !contents.contains(".frame(height: disclosureContentFrameHeight, alignment: .top)")
            || !contents.contains("private var disclosureContentFrameHeight: CGFloat?")
            || !contents.contains("private func updateMeasuredContentHeight(_ height: CGFloat)")
            || !contents.contains(".clipped()")
        {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "settings disclosures must share the animated tappable disclosure primitive"
                )
            )
        }

    }

    if fileName == "GeneralSettingsView.swift" {
        if let activeControllersBlock = sourceBlock(
            in: contents,
            from: "SettingsAnimatedDisclosure(isExpanded: $showOwnership)",
            to: "} header: {"
        ) {
            if !activeControllersBlock.contains("activeControllersSummary")
                || !activeControllersBlock.contains("activeControllersContent")
            {
                violations.append(
                    Violation(
                        file: file,
                        line: 1,
                        message: "Active Controllers must use the animated settings disclosure primitive"
                    )
                )
            }
        } else {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "GeneralSettingsView must keep Active Controllers in an animated disclosure"
                )
            )
        }

        if contents.contains("Current Owners")
            || contents.contains("Active fan writers by priority.")
            || contents.contains("Runs as root to read and write SMC fan keys.")
        {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "GeneralSettingsView must use Active Controllers terminology and footer copy"
                )
            )
        }

        if !contents.contains("Text(\"Active Controllers\")")
            || !contents.contains("SettingsDescription(text: activeControllersFooterText)")
            || !contents.contains(
                "\"Shows which app or service is currently controlling each fan. \""
            )
            || !contents.contains(
                "\"If another controller has higher priority, Fan Curve may wait before applying changes.\""
            )
        {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "GeneralSettingsView must explain Active Controllers with the approved footer"
                )
            )
        }
    }

    if fileName == "AdvancedSettingsView.swift" {
        if let extendedRangeBlock = sourceBlock(
            in: contents,
            from: "private var extendedRangeConfigurationSection: some View",
            to: "private var extendedRangeConfigurationBinding: Binding<Bool>"
        ) {
            if !matches(
                extendedRangeBlock,
                #"SettingsToggleDescriptionRow\s*\(\s*title:\s*"Allow configuring extended ranges""#
            ) {
                violations.append(
                    Violation(
                        file: file,
                        line: 1,
                        message: "Fan Range Limits must use a settings toggle-description row for extended range access"
                    )
                )
            }

            if !extendedRangeBlock.contains("isOn: extendedRangeConfigurationBinding")
                || !extendedRangeBlock.contains("AppAccessibilityIdentifier.Settings.extendedRangeAccess")
            {
                violations.append(
                    Violation(
                        file: file,
                        line: 1,
                        message: "Extended range access must retain its settings binding and accessibility identifier"
                    )
                )
            }

            if !extendedRangeBlock.contains("Shows Overdrive and Underdrive controls in the dashboard.")
                || !extendedRangeBlock.contains("increase wear or reduce cooling")
            {
                violations.append(
                    Violation(
                        file: file,
                        line: 1,
                        message: "Extended range access must explain the dashboard controls and their risks"
                    )
                )
            }

            if !matches(
                extendedRangeBlock,
                #"\}\s*header:\s*\{\s*Text\("Fan Range Limits"\)"#
            ) {
                violations.append(
                    Violation(
                        file: file,
                        line: 1,
                        message: "Extended range access must retain the Fan Range Limits section header"
                    )
                )
            }
        } else {
            violations.append(
                Violation(
                    file: file,
                    line: 1,
                    message: "AdvancedSettingsView must define the extended range access section before its binding"
                )
            )
        }
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

        if matches(line, #"\bSlider\s*\("#), !isSettingsComponents {
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
