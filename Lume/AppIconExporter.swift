//
//  AppIconExporter.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI

#if DEBUG
struct AppIconExporter: View {
    @State private var exported = false
    @State private var progress: Double = 0
    @State private var status = String(localized: "Ready to export")

    private let specs: [(CGFloat, CGFloat, String)] = [
        (1024, 1, "AppIcon-1024"),
        (512,  1, "AppIcon-512"),
        (512,  2, "AppIcon-512@2x"),
        (256,  1, "AppIcon-256"),
        (256,  2, "AppIcon-256@2x"),
        (128,  1, "AppIcon-128"),
        (128,  2, "AppIcon-128@2x"),
        (32,   1, "AppIcon-32"),
        (32,   2, "AppIcon-32@2x"),
        (16,   1, "AppIcon-16"),
        (16,   2, "AppIcon-16@2x"),
    ]

    private var outputURL: URL {
        let baseDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDir.appendingPathComponent("LumeIcons")
    }

    private var copyCommand: String {
        "cp ~/Desktop/LumeIcons/*.png \"/Users/samuelbacaro/Desktop/Lume/Lume/Lume/Assets.xcassets/AppIcon.appiconset/\""
    }

    var body: some View {
        VStack(spacing: 24) {
            AppIconView(size: 200)
                .shadow(
                    color: Color(red: 0.95, green: 0.43, blue: 0.10).opacity(0.6),
                    radius: 30, y: 8
                )

            VStack(spacing: 6) {
                Text("Lume — Icon Exporter")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(String(localized: "Exports to ~/Desktop/LumeIcons/"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            if progress > 0 {
                ProgressView(value: min(progress, 1.0))
                    .tint(Color(red: 0.95, green: 0.43, blue: 0.10))
                    .frame(width: 280)
            }

            Text(status)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(status.hasPrefix("✓") ? .green : .secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 32)

            // Buttons
            HStack(spacing: 12) {
                Button("1. Exportar PNGs") {
                    Task { await exportAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.43, blue: 0.10))
                .disabled(exported)

                if exported {
                    Button(String(localized: "Open folder")) {
                        NSWorkspace.shared.open(outputURL)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Step 2 — copy command
            if exported {
                VStack(alignment: .leading, spacing: 8) {
                    Label("2. Cole este comando no Terminal", systemImage: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(copyCommand)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copyCommand, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Copiar comando")
                    }
                    .padding(10)
                    .background(
                        Color.black.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                    // Botão que abre o Terminal e cola o comando automaticamente
                    Button("Executar no Terminal automaticamente") {
                        runInTerminal()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity)
                }
                .padding(14)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            // AccentColor swatches
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "ACCENTCOLOR — already applied in the project"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)

                HStack(spacing: 12) {
                    accentSwatch(
                        color: Color(red: 0.949, green: 0.431, blue: 0.103),
                        label: "Light",
                        hex: "#F26E1A"
                    )
                    accentSwatch(
                        color: Color(red: 1.0, green: 0.502, blue: 0.122),
                        label: "Dark",
                        hex: "#FF8020"
                    )
                }
            }
            .padding(14)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .padding(32)
        .frame(width: 420)
        .background(Color(white: 0.10))
        .animation(.easeInOut(duration: 0.3), value: exported)
    }

    // MARK: - Export to Desktop

    @MainActor
    private func exportAll() async {
        progress = 0.01
        exported = false

        // Cria a pasta de output
        do {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true
            )
        } catch {
            status = "Erro ao criar pasta: \(error.localizedDescription)"
            return
        }

        for (index, spec) in specs.enumerated() {
            let (points, scale, name) = spec
            let pixelSize = points * scale

            status = "Renderizando \(name).png…"

            let view = AppIconView(size: pixelSize)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0
            renderer.proposedSize = .init(width: pixelSize, height: pixelSize)

            let url = outputURL.appendingPathComponent("\(name).png")

            guard let nsImage = renderer.nsImage,
                  let tiff = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                status = "Erro ao renderizar \(name)"
                return
            }

            do {
                try png.write(to: url)
            } catch {
                status = "Erro ao salvar \(name): \(error.localizedDescription)"
                return
            }

            progress = Double(index + 1) / Double(specs.count)
            try? await Task.sleep(for: .milliseconds(30))
        }

        status = String(localized: "✓ \(specs.count) files in ~/Desktop/LumeIcons/\nNow copy them to Assets.xcassets")
        exported = true
    }

    // MARK: - Run in Terminal

    private func runInTerminal() {
        // Usa osascript para abrir o Terminal e executar o comando de cópia
        let script = """
        tell application "Terminal"
            activate
            do script "\(copyCommand)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let err = error {
            status = "Erro ao abrir Terminal: \(err)"
        } else {
            status = "✓ Comando enviado ao Terminal!"
        }
    }

    // MARK: - Accent Swatch

    private func accentSwatch(color: Color, label: String, hex: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)
                .frame(width: 36, height: 36)
                .shadow(color: color.opacity(0.5), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(hex)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copiar hex")
        }
    }
}

#Preview("Icon Exporter") {
    AppIconExporter()
}

#Preview("Icon — 1024pt") {
    AppIconView(size: 512)
        .frame(width: 512, height: 512)
        .background(Color(white: 0.08))
}

#Preview("Icon — Sizes") {
    HStack(spacing: 16) {
        ForEach([128, 64, 32, 16], id: \.self) { size in
            VStack(spacing: 6) {
                AppIconView(size: CGFloat(size))
                Text("\(size)pt")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(24)
    .background(Color(white: 0.12))
}
#endif
