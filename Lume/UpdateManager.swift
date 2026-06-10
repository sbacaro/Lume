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

    private let githubOwner = "samuelbacaro"
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

    func checkForUpdates() async {
        guard !isChecking else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < checkInterval { return }

        isChecking = true
        error = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()
            if isNewer(release.version, than: currentVersion) && release.version != dismissedVersion {
                availableRelease = release
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func checkForUpdatesForced() async {
        lastChecked = nil
        availableRelease = nil
        await checkForUpdates()
    }

    func dismiss() {
        if let version = availableRelease?.version {
            dismissedVersion = version
            UserDefaults.standard.set(version, forKey: "lume_dismissed_update_version")
        }
        availableRelease = nil
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

    // MARK: - GitHub API

    private func fetchLatestRelease() async throws -> AppRelease {
        let url = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw http.statusCode == 404 ? UpdateError.noReleasesFound : UpdateError.httpError(http.statusCode)
        }

        let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return json.toAppRelease()
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
        case .invalidResponse:  return "Resposta inválida do GitHub"
        case .noReleasesFound:  return "Nenhuma versão publicada encontrada"
        case .httpError(let c): return "Erro HTTP \(c) ao verificar atualizações"
        case .noDownloadAsset:  return "Arquivo de download não encontrado no release"
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
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, prerelease, assets
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
