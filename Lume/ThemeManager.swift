//
//  ThemeManager.swift
//  Lume
//
//  Personalização de tema: cor de acento e modo de aparência (claro/escuro/sistema).
//  Persistido via @AppStorage e aplicado na raiz da interface.
//

import SwiftUI

// MARK: - Chaves de armazenamento

enum ThemeKeys {
    static let accent = "lume.accent"
    static let appearance = "lume.appearance"
}

// MARK: - Cor de acento

enum AccentChoice: String, CaseIterable, Identifiable {
    case clay, blue, purple, green, pink, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clay:     return "Terracota"
        case .blue:     return "Azul"
        case .purple:   return "Roxo"
        case .green:    return "Verde"
        case .pink:     return "Rosa"
        case .graphite: return "Grafite"
        }
    }

    var color: Color {
        switch self {
        case .clay:     return Color(red: 0.92, green: 0.52, blue: 0.30)
        case .blue:     return Color(red: 0.20, green: 0.52, blue: 0.96)
        case .purple:   return Color(red: 0.55, green: 0.38, blue: 0.92)
        case .green:    return Color(red: 0.20, green: 0.72, blue: 0.50)
        case .pink:     return Color(red: 0.92, green: 0.36, blue: 0.62)
        case .graphite: return Color(red: 0.40, green: 0.42, blue: 0.48)
        }
    }
}

// MARK: - Modo de aparência

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light:  return "Claro"
        case .dark:   return "Escuro"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Helpers de leitura

enum ThemeManager {
    static var accent: AccentChoice {
        AccentChoice(rawValue: UserDefaults.standard.string(forKey: ThemeKeys.accent) ?? "") ?? .clay
    }
    static var appearance: AppearanceChoice {
        AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: ThemeKeys.appearance) ?? "") ?? .system
    }
}
