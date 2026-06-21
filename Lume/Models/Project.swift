//
//  Project.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: String = UUID().uuidString
    var name: String
    var icon: String = "folder"
    var systemPrompt: String = "You are a helpful assistant."
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Absolute path to this project's folder on disk (e.g. ~/Lume/my-project)
    var localPath: String = ""

    @Relationship(deleteRule: .cascade)
    var conversations: [Conversation] = []

    init(
        name: String,
        icon: String = "folder",
        systemPrompt: String = "You are a helpful assistant.",
        localPath: String = ""
    ) {
        self.name = name
        self.icon = icon
        self.systemPrompt = systemPrompt
        self.localPath = localPath
    }

    /// The URL of this project's folder on disk. Nil if not yet linked.
    var localURL: URL? {
        localPath.isEmpty ? nil : URL(fileURLWithPath: localPath)
    }
}
