//
//  Artifact.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation
import SwiftData

enum ArtifactType: String, Codable {
    case html
    case svg
    case javascript
    case css
    case react       // JSX/TSX — renderizado via CDN no webview
    case mermaid     // Diagramas
    case markdown
    case unknown
}

@Model
final class Artifact {
    var id: String = UUID().uuidString
    var title: String
    var rawType: String
    var content: String
    var createdAt: Date = Date()
    var message: Message?

    var type: ArtifactType {
        ArtifactType(rawValue: rawType) ?? .unknown
    }

    init(title: String, type: ArtifactType, content: String) {
        self.title = title
        self.rawType = type.rawValue
        self.content = content
    }
}
