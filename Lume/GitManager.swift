//
//  GitManager.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

actor GitManager {
    static let shared = GitManager()

    struct GitStatus {
        let branch: String
        let staged: [String]
        let modified: [String]
        let untracked: [String]
        let ahead: Int
        let behind: Int

        var summary: String {
            var parts = ["Branch: \(branch)"]
            if !staged.isEmpty    { parts.append("Staged: \(staged.count) files") }
            if !modified.isEmpty  { parts.append("Modified: \(modified.count) files") }
            if !untracked.isEmpty { parts.append("Untracked: \(untracked.count) files") }
            if ahead  > 0         { parts.append("↑\(ahead) ahead") }
            if behind > 0         { parts.append("↓\(behind) behind") }
            return parts.joined(separator: " · ")
        }
    }

    private init() {}

    // MARK: - Detection

    func isGitRepo(at path: String) async -> Bool {
        let r = await Task.detached {
            Shell.git("git -C \"\(path)\" rev-parse --is-inside-work-tree 2>/dev/null")
        }.value
        return r.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func status(at path: String) async -> GitStatus? {
        guard await isGitRepo(at: path) else { return nil }

        let branchR = await Task.detached { Shell.git("git -C \"\(path)\" branch --show-current") }.value
        let statusR = await Task.detached { Shell.git("git -C \"\(path)\" status --porcelain") }.value
        let abR     = await Task.detached {
            Shell.git("git -C \"\(path)\" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null")
        }.value

        let branch      = branchR.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusLines = statusR.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let ab          = abR.output.components(separatedBy: "\t")

        var staged: [String]    = []
        var modified: [String]  = []
        var untracked: [String] = []

        for line in statusLines {
            guard line.count >= 3 else { continue }
            let x    = String(line.prefix(1))
            let y    = String(line.dropFirst(1).prefix(1))
            let file = String(line.dropFirst(3))
            if x != " " && x != "?" { staged.append(file) }
            if y == "M"             { modified.append(file) }
            if x == "?"             { untracked.append(file) }
        }

        return GitStatus(
            branch:    branch.isEmpty ? "HEAD" : branch,
            staged:    staged,
            modified:  modified,
            untracked: untracked,
            ahead:     Int(ab.first ?? "0") ?? 0,
            behind:    Int(ab.last  ?? "0") ?? 0
        )
    }

    func diff(at path: String, staged: Bool = false) async -> String {
        let cmd = staged ? "git -C \"\(path)\" diff --cached" : "git -C \"\(path)\" diff"
        return await Task.detached { Shell.git(cmd) }.value.output
    }

    func log(at path: String, count: Int = 10) async -> String {
        await Task.detached { Shell.git("git -C \"\(path)\" log --oneline -\(count)") }.value.output
    }

    // MARK: - Operations

    func stage(files: [String], at path: String) async -> ToolResult {
        let list = files.map { "\"\($0)\"" }.joined(separator: " ")
        let r = await Task.detached { Shell.git("git -C \"\(path)\" add \(list)") }.value
        return r.exitCode == 0
            ? Shell.success("Staged: \(list)")
            : Shell.failure(r.output)
    }

    func commit(message: String, at path: String) async -> ToolResult {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        let r = await Task.detached { Shell.git("git -C \"\(path)\" commit -m \"\(escaped)\"") }.value
        return r.exitCode == 0
            ? Shell.success(r.output)
            : Shell.failure(r.output)
    }

    func push(at path: String) async -> ToolResult {
        let r = await Task.detached { Shell.git("git -C \"\(path)\" push") }.value
        return r.exitCode == 0
            ? Shell.success("Pushed successfully")
            : Shell.failure(r.output)
    }

    func createBranch(name: String, at path: String) async -> ToolResult {
        let r = await Task.detached { Shell.git("git -C \"\(path)\" checkout -b \(name)") }.value
        return r.exitCode == 0
            ? Shell.success("Created branch: \(name)")
            : Shell.failure(r.output)
    }
}
