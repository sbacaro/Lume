//
//  ArtifactPanelView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import WebKit

struct ArtifactPanelView: View {
    let artifact: Artifact
    @State private var selectedTab: ArtifactTab = .preview
    @State private var copied = false
    @State private var webViewID = UUID() // força reload

    enum ArtifactTab { case preview, source }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch selectedTab {
            case .preview:
                ArtifactWebView(artifact: artifact)
                    .id(webViewID)
            case .source:
                ArtifactSourceView(content: artifact.content)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: artifactIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                )

            Text(artifact.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Reload
            Button {
                webViewID = UUID()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reload")

            Picker("", selection: $selectedTab) {
                Text("Preview").tag(ArtifactTab.preview)
                Text("Code").tag(ArtifactTab.source)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)

            Button(action: copySource) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy code")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor))
    }

    private var artifactIcon: String {
        switch artifact.type {
        case .html:       return "globe"
        case .svg:        return "square.on.square.squareshape.controlhandles"
        case .javascript: return "chevron.left.forwardslash.chevron.right"
        case .css:        return "paintbrush"
        case .react:      return "atom"
        case .mermaid:    return "arrow.triangle.branch"
        case .markdown:   return "doc.text"
        case .unknown:    return "doc"
        }
    }

    private func copySource() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(artifact.content, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }
}

// MARK: - WebView

struct ArtifactWebView: NSViewRepresentable {
    let artifact: Artifact

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(buildHTML(), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated,
               let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }

    private func buildHTML() -> String {
        switch artifact.type {
        case .html:
            return injectBase(into: artifact.content)

        case .svg:
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>body{margin:0;display:flex;align-items:center;justify-content:center;
            min-height:100vh;background:#fff;}svg{max-width:100%;height:auto;}</style>
            </head><body>\(artifact.content)</body></html>
            """

        case .css:
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>\(artifact.content)</style></head>
            <body>
            <div class="preview">
              <h1>Heading 1</h1><h2>Heading 2</h2>
              <p>Paragraph text with <strong>bold</strong> and <em>italic</em>.</p>
              <button>Button</button>
              <a href="#">Link</a>
              <ul><li>Item one</li><li>Item two</li></ul>
            </div>
            </body></html>
            """

        case .react:
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <script src="https://unpkg.com/react@18/umd/react.development.js"></script>
            <script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
            <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
            <style>body{font-family:-apple-system,sans-serif;padding:16px;}</style>
            </head><body>
            <div id="root"></div>
            <script type="text/babel">
            \(artifact.content)
            const rootEl = document.getElementById('root');
            const root = ReactDOM.createRoot(rootEl);
            // Try to find exported/declared component
            const Component = typeof App !== 'undefined' ? App :
                              typeof Component !== 'undefined' ? Component :
                              () => React.createElement('p', null, 'Export a component as App');
            root.render(React.createElement(Component));
            </script>
            </body></html>
            """

        case .mermaid:
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
            <style>body{margin:0;padding:24px;background:#fff;display:flex;
            justify-content:center;}
            .mermaid{max-width:100%;}</style>
            </head><body>
            <div class="mermaid">\(artifact.content)</div>
            <script>mermaid.initialize({startOnLoad:true,theme:'default'});</script>
            </body></html>
            """

        case .javascript:
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>body{font-family:-apple-system,sans-serif;padding:16px;background:#fff;}
            #output{white-space:pre-wrap;font-family:monospace;font-size:13px;}</style>
            </head><body><div id="output"></div>
            <script>
            const _log=console.log.bind(console);
            console.log=(...a)=>{
              document.getElementById('output').textContent+=a.map(String).join(' ')+'\\n';
              _log(...a);
            };
            try{\(artifact.content)}catch(e){
              document.getElementById('output').textContent='Error: '+e.message;
            }
            </script></body></html>
            """

        default:
            return "<html><body><pre>\(artifact.content)</pre></body></html>"
        }
    }

    private func injectBase(into html: String) -> String {
        let base = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>*,*::before,*::after{box-sizing:border-box;}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;margin:0;padding:0;}</style>
        """
        if html.contains("<head>") {
            return html.replacingOccurrences(of: "<head>", with: "<head>\(base)")
        }
        return "<html><head>\(base)</head><body>\(html)</body></html>"
    }
}

// MARK: - Source View

struct ArtifactSourceView: View {
    let content: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.textBackgroundColor))
    }
}
