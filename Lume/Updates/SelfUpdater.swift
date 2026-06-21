//
//  SelfUpdater.swift
//  Lume
//
//  Auto-atualização SEM Sparkle e SEM Developer ID.
//
//  O app baixa o DMG do GitHub Release, VERIFICA o download com a chave EdDSA
//  (Ed25519) do projeto — a mesma `SUPublicEDKey` já embutida no Info.plist e a
//  `sparkle:edSignature` publicada no appcast — e então troca o próprio `.app` e
//  reabre. Como o app é NÃO-ASSINADO (sem Developer ID), o script de troca remove
//  o atributo de quarentena para o Gatekeeper não bloquear a reabertura.
//
//  Segurança: a autenticidade vem da verificação Ed25519 (só quem tem a chave
//  privada consegue assinar um release válido) — não dependemos de assinatura da
//  Apple. Se a chave pública não estiver configurada, caímos para verificação só
//  por tamanho (HTTPS + tamanho do appcast).
//

import Foundation
import AppKit
import CryptoKit
import Observation

@MainActor
@Observable
final class SelfUpdater {
    static let shared = SelfUpdater()
    private init() {}

    enum Phase: Equatable {
        case idle, downloading, verifying, installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var isBusy: Bool {
        switch phase { case .downloading, .verifying, .installing: return true; default: return false }
    }

    var statusText: String {
        switch phase {
        case .idle:        return ""
        case .downloading: return String(localized: "Downloading update…")
        case .verifying:   return String(localized: "Verifying signature…")
        case .installing:  return String(localized: "Installing…")
        case .failed(let m): return String(localized: "Update failed: \(m)")
        }
    }

    /// URL do appcast (mesma do feed do Sparkle) — só para pegar tamanho + assinatura EdDSA.
    private let feedURL = "https://raw.githubusercontent.com/sbacaro/Lume/main/appcast.xml"

    // MARK: - Fluxo principal

    func installUpdate(_ release: AppRelease) async {
        guard !isBusy else { return }
        phase = .downloading
        do {
            // 1) Tamanho + assinatura esperados (do appcast) p/ verificar o download.
            let entry = try await fetchAppcastEntry(version: release.version)
            let url = entry.url ?? release.downloadURL

            // 2) Baixa o DMG.
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw Err.msg(String(localized: "Download failed (HTTP \(code))."))
            }
            let dmg = FileManager.default.temporaryDirectory
                .appendingPathComponent("Lume-update-\(UUID().uuidString).dmg")
            try? FileManager.default.removeItem(at: dmg)
            try FileManager.default.moveItem(at: tmp, to: dmg)

            // 3) Verifica integridade (tamanho) e autenticidade (Ed25519).
            phase = .verifying
            try verify(dmg: dmg, expected: entry)

            // 4) Monta, troca o .app e agenda a reabertura (fora da MainActor).
            phase = .installing
            let dest = Bundle.main.bundlePath
            try await Task.detached(priority: .userInitiated) {
                try SelfUpdater.installFromDMG(dmg, destBundlePath: dest)
            }.value

            // 5) Encerra; o script de troca espera o app sair, troca o bundle e reabre.
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)
        } catch {
            phase = .failed((error as? Err)?.text ?? error.localizedDescription)
        }
    }

    func reset() { if !isBusy { phase = .idle } }

    // MARK: - Verificação (Ed25519 + tamanho)

    private func verify(dmg: URL, expected: AppcastEntry) throws {
        let data = try Data(contentsOf: dmg)

        if let len = expected.length, len > 0, data.count != len {
            throw Err.msg(String(localized: "Downloaded size doesn't match the release (\(data.count) vs \(len))."))
        }

        // Chave pública do projeto (mesma do Sparkle). Sem ela, não há como verificar
        // autenticidade — seguimos apenas com a checagem de tamanho acima.
        guard let pubB64 = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String,
              let pubData = Data(base64Encoded: pubB64) else { return }

        guard let sigB64 = expected.edSignature, let sig = Data(base64Encoded: sigB64) else {
            throw Err.msg(String(localized: "No signature for this version in the appcast."))
        }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
        guard key.isValidSignature(sig, for: data) else {
            throw Err.msg(String(localized: "The update failed signature verification."))
        }
    }

    // MARK: - Appcast (tamanho + assinatura EdDSA por versão)

    struct AppcastEntry { var version: String; var url: URL?; var length: Int?; var edSignature: String? }

    private func fetchAppcastEntry(version: String) async throws -> AppcastEntry {
        guard let url = URL(string: feedURL) else { throw Err.msg("Invalid feed URL") }
        let (data, _) = try await URLSession.shared.data(from: url)
        let entries = AppcastParser.parse(data)
        if let match = entries.first(where: { $0.version == version }) { return match }
        if let newest = entries.first { return newest }     // topo = mais novo
        throw Err.msg("No entries found in the appcast.")
    }

    // MARK: - Instalação (montar → preparar → trocar → reabrir)

    nonisolated static func installFromDMG(_ dmg: URL, destBundlePath: String) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("LumeUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let mount = work.appendingPathComponent("mnt").path

        let (ac, ao) = try run("/usr/bin/hdiutil",
                               ["attach", dmg.path, "-nobrowse", "-noverify", "-mountpoint", mount])
        guard ac == 0 else { throw Err.msg("Failed to mount the DMG: \(ao)") }
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount, "-force"]) }

        let contents = (try? fm.contentsOfDirectory(atPath: mount)) ?? []
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw Err.msg("No .app found inside the DMG.")
        }
        let newApp = mount + "/" + appName
        guard fm.fileExists(atPath: newApp + "/Contents/Info.plist") else {
            throw Err.msg("The downloaded app looks invalid.")
        }

        // Copia para uma área de staging (ditto preserva symlinks/atributos do bundle).
        let staged = work.appendingPathComponent(appName).path
        let (dc, dout) = try run("/usr/bin/ditto", [newApp, staged])
        guard dc == 0 else { throw Err.msg("Failed to stage the app: \(dout)") }

        let destDir = (destBundlePath as NSString).deletingLastPathComponent
        guard fm.isWritableFile(atPath: destDir) else {
            throw Err.msg("No write permission for \(destDir). Move Lume to your user's Applications folder and try again.")
        }

        // Script destacado: espera o app sair, troca o bundle (com rollback), remove a
        // quarentena (app não-assinado → senão o Gatekeeper bloqueia) e reabre.
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        PID="$1"; STAGED="$2"; DEST="$3"
        for i in $(seq 1 200); do /bin/kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        /bin/rm -rf "$DEST.old" 2>/dev/null
        /bin/mv "$DEST" "$DEST.old" 2>/dev/null
        if /usr/bin/ditto "$STAGED" "$DEST"; then
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
          /bin/rm -rf "$DEST.old" 2>/dev/null
        else
          /bin/rm -rf "$DEST" 2>/dev/null
          /bin/mv "$DEST.old" "$DEST" 2>/dev/null
        fi
        /usr/bin/open "$DEST"
        """
        let scriptPath = work.appendingPathComponent("swap.sh").path
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        let cmd = "nohup /bin/bash \(q(scriptPath)) \(pid) \(q(staged)) \(q(destBundlePath)) >/tmp/lume-update.log 2>&1 &"
        _ = try run("/bin/bash", ["-c", cmd])
    }

    // MARK: - Helpers de shell

    nonisolated static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func run(_ path: String, _ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    enum Err: Error { case msg(String); var text: String { if case .msg(let s) = self { return s }; return "" } }
}

// MARK: - Appcast XML parser (mínimo: version + enclosure)

private final class AppcastParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> [SelfUpdater.AppcastEntry] {
        let p = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.parse()
        return p.entries
    }

    var entries: [SelfUpdater.AppcastEntry] = []
    private var current: SelfUpdater.AppcastEntry?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName qn: String?, attributes a: [String: String]) {
        switch el {
        case "item":
            current = SelfUpdater.AppcastEntry(version: "", url: nil, length: nil, edSignature: nil)
        case "enclosure":
            current?.url = a["url"].flatMap { URL(string: $0) }
            current?.length = a["length"].flatMap { Int($0) }
            current?.edSignature = a["sparkle:edSignature"] ?? a["edSignature"]
        default:
            break
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName qn: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if el == "sparkle:shortVersionString" { current?.version = t }
        if el == "item", let c = current { entries.append(c); current = nil }
    }
}
