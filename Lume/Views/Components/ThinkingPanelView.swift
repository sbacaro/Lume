// ThinkingPanelView.swift
import SwiftUI

struct ThinkingPanelView: View {
    let tracker: ThinkingTracker
    let isStreaming: Bool

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ──────────────────────────────────────────────
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if isStreaming && tracker.isActive {
                        // Animated pulse dot
                        PulseDot()
                    } else {
                        Image(systemName: "brain")
                            .font(.lume(.footnote, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(isStreaming && tracker.isActive
                         ? (tracker.currentLabel.isEmpty ? "Thinking…" : tracker.currentLabel)
                         : String(localized: "Thinking process"))
                        .font(.lume(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.lume(.caption, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            // ── Steps list ──────────────────────────────────────────────
            if isExpanded && !tracker.steps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tracker.steps) { step in
                        ThinkingStepRow(step: step, isLast: step.id == tracker.steps.last?.id, isStreaming: isStreaming)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .frame(maxWidth: 560)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: tracker.steps.count)
    }
}

// MARK: - Step Row

private struct ThinkingStepRow: View {
    let step: ThinkingTracker.Step
    let isLast: Bool
    let isStreaming: Bool

    @State private var isDetailExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Icon
                Group {
                    if isLast && isStreaming && !step.isDone {
                        PulseDot(size: 7, color: .accentColor)
                    } else {
                        Image(systemName: step.icon)
                            .font(.lume(.footnote, weight: .medium))
                            .foregroundStyle(step.isDone ? Color.green : Color.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(width: 16)

                Text(step.label)
                    .font(.lume(.subheadline))
                    .foregroundStyle(step.isDone ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                // Expand detail if available
                if !step.detail.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isDetailExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.lume(.caption2, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isDetailExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)

            if isDetailExpanded && !step.detail.isEmpty {
                Text(step.detail)
                    .font(.lume(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
                    .padding(.bottom, 4)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Pulse Dot

struct PulseDot: View {
    var size: CGFloat = 8
    var color: Color = .accentColor
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: size * 1.8, height: size * 1.8)
                .scaleEffect(pulse ? 1.3 : 0.9)
                .opacity(pulse ? 0 : 0.6)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
