//
//  LumeBrand.swift
//  Lume
//
//  Marca visual reutilizável do Lume: o mesmo ícone do app (squircle + estrela)
//  e o loader na identidade do projeto (estrelas da cor do ícone, acendendo de
//  cima para baixo). Fonte única para avatar e loader.
//

import SwiftUI

// MARK: - Paleta da marca

enum LumeBrand {
    /// Gradiente do ícone do app — amostrado do PNG real (Assets.xcassets):
    /// rosa-coral no topo-esquerdo → pêssego-laranja na base-direita.
    static let gradient = LinearGradient(
        colors: [
            Color(red: 0.925, green: 0.549, blue: 0.557),  // rosa coral
            Color(red: 0.941, green: 0.596, blue: 0.506),  // pêssego médio
            Color(red: 0.957, green: 0.643, blue: 0.455)   // pêssego laranja
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Estrelas do loader — mesma família quente do ícone.
    static let starGradient = LinearGradient(
        colors: [
            Color(red: 0.945, green: 0.560, blue: 0.545),
            Color(red: 0.957, green: 0.643, blue: 0.455)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let glow = Color(red: 0.95, green: 0.55, blue: 0.50)
}

// MARK: - Marca do app (squircle + estrela)

/// O mesmo ícone do app — usado no avatar das mensagens do modelo.
struct LumeMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LumeBrand.gradient)
            .frame(width: size, height: size)
            .overlay(
                // Cluster de estrelas, como o ícone do app.
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: LumeBrand.glow.opacity(0.30), radius: size * 0.2, y: size * 0.07)
    }
}

// MARK: - Loader (estrelas acendendo de cima para baixo)

/// Loader na identidade do Lume: estrelas (sparkle) da cor do ícone, acendendo
/// uma de cada vez, de cima para baixo. Exibido abaixo da resposta enquanto o
/// modelo escreve.
struct StarLoaderView: View {
    var starSize: CGFloat = 22

    @State private var pulsing = false

    var body: some View {
        // Cluster de estrelas (igual ao ícone) com pulse no conjunto inteiro,
        // sem deslocamento — apenas respira (escala + opacidade), em loop.
        Image(systemName: "sparkles")
            .font(.system(size: starSize, weight: .semibold))
            .foregroundStyle(LumeBrand.starGradient)
            .scaleEffect(pulsing ? 1.0 : 0.82)
            .opacity(pulsing ? 1.0 : 0.45)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .accessibilityLabel("Gerando resposta")
    }
}
