//
//  AgentToolCallView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI

struct AgentToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — sempre visível
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    stateIcon
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(toolDisplayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(toolSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(headerBackground)

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    // Input
                    if !toolCall.input.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("INPUT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .tracking(1)

                            ForEach(
                                Array(toolCall.input.sorted(by: { $0.key < $1.key })),
                                id: \.key
                            ) { key, value in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(key)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 60, alignment: .trailing)

                                    Text(value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    // Output — FIX: unwrap result before accessing .success
                    if let result = toolCall.result {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("OUTPUT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .tracking(1)

                            ScrollView(.vertical) {
                                Text(result.output)
                                    .font(.system(size: 11, design: .monospaced))
                                    // FIX: use Color.red, not .red (which resolves to HierarchicalShapeStyle)
                                    .foregroundStyle(result.success ? Color.primary : Color.red)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
                .padding(12)
                .background(Color(.textBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .frame(maxWidth: 520)
    }

    // MARK: - State Icon

    @ViewBuilder
    private var stateIcon: some View {
        switch toolCall.state {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

        case .running:
            ProgressView()
                .scaleEffect(0.6)
                .progressViewStyle(.circular)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.green)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.red)
        }
    }

    // MARK: - Computed

    private var toolDisplayName: String {
        switch toolCall.toolName {
        case "run_shell":        return "Terminal"
        case "read_file":        return "Read File"
        case "write_file":       return "Write File"
        case "list_directory":   return "List Directory"
        case "create_directory": return "Create Directory"
        default:                 return toolCall.toolName
        }
    }

    private var toolSummary: String {
        switch toolCall.toolName {
        case "run_shell":
            return toolCall.input["command"] ?? ""
        case "read_file", "write_file", "list_directory", "create_directory":
            return toolCall.input["path"] ?? ""
        default:
            return toolCall.input.values.first ?? ""
        }
    }

    private var headerBackground: Color {
        switch toolCall.state {
        case .pending:   return Color(.controlBackgroundColor)
        case .running:   return Color.accentColor.opacity(0.06)
        case .completed: return Color.green.opacity(0.05)
        case .failed:    return Color.red.opacity(0.05)
        }
    }

    private var borderColor: Color {
        switch toolCall.state {
        case .pending:   return Color.primary.opacity(0.08)
        case .running:   return Color.accentColor.opacity(0.3)
        case .completed: return Color.green.opacity(0.2)
        case .failed:    return Color.red.opacity(0.2)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AgentToolCallView(toolCall: ToolCall(
            toolName: "run_shell",
            input: ["command": "swift build", "working_directory": "/Users/dev/MyApp"]
        ))

        AgentToolCallView(toolCall: {
            var tc = ToolCall(
                toolName: "write_file",
                input: [
                    "path": "/Users/dev/MyApp/Sources/main.swift",
                    "content": "print(\"Hello, World!\")"
                ]
            )
            tc.result = makeSuccess("File written successfully to /Users/dev/MyApp/Sources/main.swift")
            tc.state = .completed
            return tc
        }())

        AgentToolCallView(toolCall: {
            var tc = ToolCall(
                toolName: "run_shell",
                input: ["command": "npm install"]
            )
            tc.result = makeFailure("Exit 1: npm: command not found")
            tc.state = .failed
            return tc
        }())
    }
    .padding(24)
    .frame(width: 600)
}
