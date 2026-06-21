//
//  LumeType.swift
//  Lume
//
//  Fonte ÚNICA da tipografia do app. Em vez de `.font(.system(size: N))` espalhado,
//  todo texto usa um papel semântico (`.font(.lume(.body))`, `.font(.lume(.title2))`…)
//  com tamanho e peso padronizados. Cada papel é multiplicado pelo fator de zoom
//  global (LumeZoom), o que dá um "zoom in / zoom out" de acessibilidade que vale
//  para o app inteiro a partir de um único lugar.
//

import SwiftUI

// MARK: - Escala tipográfica

/// Papéis de texto do Lume. O tamanho é a referência *sem* zoom; o peso é o padrão
/// do papel e pode ser sobrescrito no ponto de uso (`.lume(.body, weight: .semibold)`).
///
/// A escala foi calibrada sobre os tamanhos já usados no app, mantendo os mais comuns
/// (9–14) em seus valores exatos e colapsando a cauda longa (15+) em poucos degraus.
enum LumeTextStyle: CaseIterable {
    case largeTitle   // 34 — heróis / telas vazias
    case title1       // 28 — títulos de tela
    case title2       // 20 — títulos de seção
    case title3       // 16 — subtítulos
    case body         // 14 — leitura confortável
    case callout      // 13 — corpo padrão da UI
    case subheadline  // 12 — texto secundário
    case footnote     // 11 — legendas / metadados
    case caption      // 10 — texto miúdo
    case caption2     //  9 — o menor

    var size: CGFloat {
        switch self {
        case .largeTitle:  return 34
        case .title1:      return 28
        case .title2:      return 20
        case .title3:      return 16
        case .body:        return 14
        case .callout:     return 13
        case .subheadline: return 12
        case .footnote:    return 11
        case .caption:     return 10
        case .caption2:    return 9
        }
    }

    /// Peso padrão do papel. Todos são `.regular` para preservar a aparência atual
    /// (quem precisava de peso já passava `weight:` no ponto de uso).
    var weight: Font.Weight { .regular }
}

// MARK: - Fator de zoom global (acessibilidade)

/// Escala de texto do app inteiro, persistida em UserDefaults. Os comandos
/// View → Zoom In/Out/Actual Size ajustam este valor; a UI relê em cada render.
enum LumeZoom {
    static let key = "ui.textZoom"
    static let minScale: CGFloat = 0.8
    static let maxScale: CGFloat = 1.6
    static let step: CGFloat = 0.1

    /// Fator atual (1.0 = 100%), sempre dentro de [minScale, maxScale].
    static var scale: CGFloat {
        let raw = (UserDefaults.standard.object(forKey: key) as? Double).map { CGFloat($0) } ?? 1.0
        return Swift.min(maxScale, Swift.max(minScale, raw))
    }

    /// Percentual inteiro para exibição (ex.: 110).
    static var percent: Int { Int((scale * 100).rounded()) }

    @discardableResult
    static func set(_ v: CGFloat) -> CGFloat {
        let clamped = Swift.min(maxScale, Swift.max(minScale, v))
        UserDefaults.standard.set(Double(clamped), forKey: key)
        return clamped
    }

    static func zoomIn()  { set(scale + step) }
    static func zoomOut() { set(scale - step) }
    static func reset()   { set(1.0) }

    static var canZoomIn: Bool  { scale < maxScale - 0.001 }
    static var canZoomOut: Bool { scale > minScale + 0.001 }
}

// MARK: - Fábrica de fontes

extension Font {
    /// Fonte de um papel semântico, já com o zoom global aplicado.
    /// - Parameters:
    ///   - style: o papel (`.body`, `.title2`, …).
    ///   - weight: sobrescreve o peso padrão do papel quando informado.
    ///   - design: família (ex.: `.monospaced` para código).
    static func lume(_ style: LumeTextStyle,
                     weight: Font.Weight? = nil,
                     design: Font.Design = .default,
                     scale: CGFloat = LumeZoom.scale) -> Font {
        .system(size: style.size * scale, weight: weight ?? style.weight, design: design)
    }

    /// Escape hatch para tamanhos fora da escala (ícones grandes, ilustrações).
    /// Continua respeitando o zoom global, mas sem papel semântico.
    static func lume(size: CGFloat,
                     weight: Font.Weight = .regular,
                     design: Font.Design = .default,
                     scale: CGFloat = LumeZoom.scale) -> Font {
        .system(size: size * scale, weight: weight, design: design)
    }
}

// MARK: - Propagação do zoom

/// Valor de ambiente espelhando `LumeZoom.scale`. Ele não é lido diretamente pelas
/// fontes (que usam o global), mas é injetado na raiz para que uma mudança de zoom
/// invalide a árvore e force o recálculo das fontes.
private struct LumeZoomKey: EnvironmentKey { static let defaultValue: CGFloat = 1.0 }

extension EnvironmentValues {
    var lumeZoom: CGFloat {
        get { self[LumeZoomKey.self] }
        set { self[LumeZoomKey.self] = newValue }
    }
}

extension View {
    /// Aplica o zoom de texto atual a uma subárvore: injeta o valor no ambiente e
    /// re-identifica o conteúdo para garantir que todas as fontes sejam recalculadas
    /// quando o usuário usa Zoom In/Out. Use uma vez, na raiz de cada cena.
    func lumeTextZoom(_ scale: CGFloat) -> some View {
        self.environment(\.lumeZoom, scale)
            .id(Int((scale * 100).rounded()))
    }
}
