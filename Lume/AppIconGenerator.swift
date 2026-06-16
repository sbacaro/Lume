//
//  AppIconGenerator.swift
//  Lume
//

import SwiftUI
import AppKit

struct AppIconGeneratorView: View {
    @State private var generated = false
    @State private var outputPath = ""

    var body: some View {
        VStack(spacing: 20) {
            LumeLogo(size: 80)

            Text("Icon Generator")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            if generated {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Icons generated successfully!")
                        .font(.headline)
                    Text(outputPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text(String(localized: "Choose a folder where the icons\nwill be saved."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Choose folder and generate") {
                    pickFolderAndGenerate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 340)
    }

    private func pickFolderAndGenerate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Choose where to save the Lume icons")
        panel.prompt = String(localized: "Save here")

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        generateIcons(in: folder)
    }

    private func generateIcons(in folder: URL) {
        let sizes: [(Int, String)] = [
            (16,   "icon_16x16"),
            (32,   "icon_16x16@2x"),
            (32,   "icon_32x32"),
            (64,   "icon_32x32@2x"),
            (128,  "icon_128x128"),
            (256,  "icon_128x128@2x"),
            (256,  "icon_256x256"),
            (512,  "icon_256x256@2x"),
            (512,  "icon_512x512"),
            (1024, "icon_512x512@2x"),
        ]

        for (size, name) in sizes {
            let nsImage = renderIcon(size: CGFloat(size))
            if let tiff = nsImage.tiffRepresentation,
               let bmp  = NSBitmapImageRep(data: tiff),
               let png  = bmp.representation(using: .png, properties: [:]) {
                let file = folder.appendingPathComponent("\(name).png")
                try? png.write(to: file)
            }
        }

        outputPath = folder.path
        generated = true
    }

    private func renderIcon(size: CGFloat) -> NSImage {
        let view = IconView(size: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        return renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
    }
}

private struct IconView: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.52, blue: 0.58),
                    Color(red: 0.96, green: 0.67, blue: 0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
