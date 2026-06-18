//
//  ArtifactDetectorTests.swift
//  LumeTests
//
//  Cobre a detecção de artifacts em blocos de código markdown.
//

import Testing
@testable import Lume

@MainActor
struct ArtifactDetectorTests {

    @Test func detectsHTMLAndExtractsTitle() {
        let text = """
        Aqui está:
        ```html
        <html><head><title>Minha Página</title></head><body>oi</body></html>
        ```
        """
        let result = ArtifactDetector.detect(in: text)
        #expect(result != nil)
        #expect(result?.type == .html)
        #expect(result?.title == "Minha Página")
    }

    @Test func detectsHTMLFallsBackToH1() {
        let text = """
        ```html
        <body><h1>Cabeçalho</h1></body>
        ```
        """
        #expect(ArtifactDetector.detect(in: text)?.title == "Cabeçalho")
    }

    @Test func detectsReactFromJSX() {
        let text = """
        ```jsx
        export default function App() { return <div/>; }
        ```
        """
        let result = ArtifactDetector.detect(in: text)
        #expect(result?.type == .react)
        #expect(result?.title == "React Component")
    }

    @Test func detectsSVGAndMermaid() {
        let svg = "```svg\n<svg></svg>\n```"
        #expect(ArtifactDetector.detect(in: svg)?.type == .svg)

        let mermaid = "```mermaid\ngraph TD; A-->B;\n```"
        #expect(ArtifactDetector.detect(in: mermaid)?.type == .mermaid)
    }

    @Test func javascriptTitleFromLeadingComment() {
        let text = "```js\n// util de soma\nfunction add(a,b){return a+b}\n```"
        let result = ArtifactDetector.detect(in: text)
        #expect(result?.type == .javascript)
        #expect(result?.title == "util de soma")
    }

    @Test func returnsNilWhenNoArtifact() {
        #expect(ArtifactDetector.detect(in: "apenas texto, sem código") == nil)
        let plainBlock = "```python\nprint('oi')\n```"  // não é tipo de artifact
        #expect(ArtifactDetector.detect(in: plainBlock) == nil)
    }

    @Test func hasArtifactDetectsFences() {
        #expect(ArtifactDetector.hasArtifact(in: "```svg\n<svg/>\n```"))
        #expect(ArtifactDetector.hasArtifact(in: "```mermaid\n```"))
        #expect(ArtifactDetector.hasArtifact(in: "sem fence") == false)
    }
}
