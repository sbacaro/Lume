//
//  LumeTheme.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI

enum LumeTheme {
    // MARK: - Earth Tone Palette
    static let sand       = Color(red: 0.95, green: 0.91, blue: 0.84)
    static let clay       = Color(red: 0.76, green: 0.60, blue: 0.47)
    static let moss       = Color(red: 0.47, green: 0.55, blue: 0.42)
    static let slate      = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let ember      = Color(red: 0.80, green: 0.45, blue: 0.30)
    static let parchment  = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let bark       = Color(red: 0.28, green: 0.22, blue: 0.18)

    // MARK: - Semantic
    static var background: Color   { Color(.windowBackgroundColor) }
    static var surface: Color      { Color(.controlBackgroundColor) }
    static var userBubble: Color   { clay.opacity(0.15) }
    static var assistantBg: Color  { Color.clear }

    // MARK: - Greeting
    static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Bom dia"
        case 12..<18: return "Boa tarde"
        case 18..<22: return "Boa noite"
        default:      return "Olá"
        }
    }

    static func greetingEmoji() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "☀️"
        case 12..<18: return "🌤️"
        case 18..<22: return "🌙"
        default:      return "✨"
        }
    }
}
