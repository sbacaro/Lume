//
//  UpdateManager.swift
//  Lume
//

import Foundation
import AppKit
import Observation

// MARK: - App Release

struct AppRelease: Sendable {
    let version: String
    let buildNumber: String
    let releaseNotes: String
    let downloadURL: URL
    let publishedAt: Date
    let isPrerelease: Bool
}

// MARK: - Update Manager

@Observable
final class UpdateManager {
    static let shared = UpdateManager()

    private let githubOwner = "sbacaro"
    private let githubRepo  = "Lume"

    var availableRelease: AppRelease? = nil
    var isChecking = false
    var lastChecked: Date? = nil
    var dismissedVersion: String? = nil
    var error: String? = nil

    private let checkInterval: TimeInterval = 3600 * 6

    private init() {
        dismissedVersion = UserDefaults.standard.string(forKey: "lume_dismissed_update_version")
    }

    // MARK: - Check for updates

    /// `force == true` é um check EXPLÍCITO do usuário (botão "Check"): ignora o
    /// throttle de 6h e a dispensa anterior — quem clica quer ver a versão nova.
    /// `force == false` é o check automático/agendado: respeita o intervalo e a
    /// versão dispensada (não reabre um aviso que o usuário já fechou).
    func checkForUpdates(force: Bool = false) async {
        guard !isChecking else { return }
        if !force, let last = lastChecked, Date().timeIntervalSince(last) < checkInterval { return }

        isChecking = true
        error = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()
            if isNewer(release.version, than: currentVersion) {
                if force {
                    // Check explícito: sempre mostra e desfaz a dispensa dessa versão.
                    if release.version == dismissedVersion { clearDismissed() }
                    availableRelease = release
                } else if release.version != dismissedVersion {
                    availableRelease = release
                }
            } else {
                // Já estamos na última (ou mais nova): nada a oferecer.
                availableRelease = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func checkForUpdatesForced() async {
        lastChecked = nil
        availableRelease = nil
        await checkForUpdates(force: true)
    }

    func dismiss() {
        if let version = availableRelease?.version {
            dismissedVersion = version
            UserDefaults.standard.set(version, forKey: "lume_dismissed_update_version")
        }
        availableRelease = nil
    }

    private func clearDismissed() {
        dismissedVersion = nil
        UserDefaults.standard.removeObject(forKey: "lume_dismissed_update_version")
    }

    func openDownloadPage() {
        guard let url = availableRelease?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Current version

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Versão unificada para exibição: marketing + build juntos (ex.: "1.4.1.16").
    var fullVersion: String {
        "\(currentVersion).\(currentBuild)"
    }

    // MARK: - GitHub API

    private func fetchLatestRelease() async throws -> AppRelease {
        // 1) Tenta o endpoint "latest" (ignora drafts e prereleases).
        if let latest = try await requestRelease(path: "releases/latest") {
            return latest
        }
        // 2) Fallback: o "latest" devolveu 404 (ex.: repo só com prereleases,
        //    ou release recém-publicado ainda propagando). Usa a lista completa.
        let releases = try await requestReleasesList()
        var newest: AppRelease?
        for release in releases where newest == nil || isNewer(release.version, than: newest!.version) {
            newest = release
        }
        guard let result = newest else { throw UpdateError.noReleasesFound }
        return result
    }

    /// Busca um único release; retorna `nil` em 404 (sem release).
    private func requestRelease(path: String) async throws -> AppRelease? {
        let (data, http) = try await apiGet(path)
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw UpdateError.httpError(http.statusCode) }
        return try JSONDecoder().decode(GitHubRelease.self, from: data).toAppRelease()
    }

    /// Lista os releases publicados (exclui drafts).
    private func requestReleasesList() async throws -> [AppRelease] {
        let (data, http) = try await apiGet("releases?per_page=30")
        guard http.statusCode == 200 else {
            throw http.statusCode == 404 ? UpdateError.noReleasesFound : UpdateError.httpError(http.statusCode)
        }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        return releases.filter { !($0.draft ?? false) }.map { $0.toAppRelease() }
    }

    private func apiGet(_ path: String) async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/\(path)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Lume-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        return (data, http)
    }

    // MARK: - Version comparison (semver)

    func isNewer(_ version: String, than current: String) -> Bool {
        let newParts  = version.split(separator: ".").compactMap { Int($0) }
        let currParts = current.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(newParts.count, currParts.count)
        for i in 0..<maxLen {
            let n = i < newParts.count  ? newParts[i]  : 0
            let c = i < currParts.count ? currParts[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleasesFound
    case httpError(Int)
    case noDownloadAsset

    var errorDescription: String? {
        switch self {
        case .invalidResponse:  return String(localized: "Invalid response from GitHub")
        case .noReleasesFound:  return String(localized: "No published release found")
        case .httpError(let c): return String(localized: "HTTP error \(c) while checking for updates")
        case .noDownloadAsset:  return String(localized: "Download file not found in the release")
        }
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String
    let body: String?
    let htmlUrl: String
    let publishedAt: String
    let prerelease: Bool
    let draft: Bool?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, prerelease, draft, assets
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
    }

    func toAppRelease() -> AppRelease {
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        let downloadURL: URL
        if let dmg = assets.first(where: { $0.name.hasSuffix(".dmg") }) {
            downloadURL = URL(string: dmg.browserDownloadUrl) ?? URL(string: htmlUrl)!
        } else if let zip = assets.first(where: { $0.name.hasSuffix(".zip") }) {
            downloadURL = URL(string: zip.browserDownloadUrl) ?? URL(string: htmlUrl)!
        } else {
            downloadURL = URL(string: htmlUrl)!
        }

        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: publishedAt) ?? Date()

        return AppRelease(
            version: version,
            buildNumber: "",
            releaseNotes: body ?? "",
            downloadURL: downloadURL,
            publishedAt: date,
            isPrerelease: prerelease
        )
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}
