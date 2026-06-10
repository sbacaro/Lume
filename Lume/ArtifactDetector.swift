//
//  ArtifactDetector.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import Foundation

struct ArtifactDetector {

    struct DetectedArtifact {
        let title: String
        let type: ArtifactType
        let content: String
        let range: Range<String.Index>
    }

    static func detect(in text: String) -> DetectedArtifact? {
        let pattern = /```(html|svg|javascript|js|css|jsx|tsx|react|mermaid)\n([\s\S]*?)```/
        guard let match = text.firstMatch(of: pattern) else { return nil }

        let lang = String(match.1).lowercased()
        let content = String(match.2)

        let type: ArtifactType = switch lang {
        case "html":                    .html
        case "svg":                     .svg
        case "javascript", "js":        .javascript
        case "css":                     .css
        case "jsx", "tsx", "react":     .react
        case "mermaid":                 .mermaid
        default:                        .unknown
        }

        guard type != .unknown else { return nil }

        let title = extractTitle(from: content, type: type)
        return DetectedArtifact(title: title, type: type, content: content, range: match.range)
    }

    static func hasArtifact(in text: String) -> Bool {
        ["```html", "```svg", "```javascript", "```js",
         "```css", "```jsx", "```tsx", "```react", "```mermaid"]
            .contains(where: { text.contains($0) })
    }

    private static func extractTitle(from content: String, type: ArtifactType) -> String {
        switch type {
        case .html:
            if let m = content.firstMatch(of: /<title>(.*?)<\/title>/) { return String(m.1) }
            if let m = content.firstMatch(of: /<h1[^>]*>(.*?)<\/h1>/)  { return String(m.1) }
            return "HTML Preview"
        case .svg:      return "SVG Graphic"
        case .css:      return "Stylesheet"
        case .react:    return "React Component"
        case .mermaid:  return "Diagram"
        case .javascript:
            let first = content.components(separatedBy: "\n").first ?? ""
            if first.hasPrefix("//") { return String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            return "JavaScript"
        default:        return "Artifact"
        }
    }
}
