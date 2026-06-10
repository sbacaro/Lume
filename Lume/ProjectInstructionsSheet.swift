//
//  ProjectInstructionsSheet.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI

struct ProjectInstructionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: project.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LumeTheme.clay)
                Text("Instruções do Projeto")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("Estas instruções são enviadas ao assistente no início de cada conversa neste projeto. Use-as para definir tom, formato ou regras de comportamento.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Instruções do Assistente")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $project.systemPrompt)
                    .font(.system(size: 13))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(
                        Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("Concluído") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
