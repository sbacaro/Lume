//
//  AppIconView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI

// MARK: - App Icon View
// Renderiza o ícone do Lume em qualquer tamanho.
// Use AppIconPreview para exportar em múltiplas resoluções.

struct AppIconView: View {
    var size: CGFloat = 1024

    private var s: CGFloat { size }

    var body: some View {
        ZStack {
            // 1. Background — deep gradient, escuro mas rico
            background

            // 2. Liquid Glass orb — elemento central
            glassOrb

            // 3. Spark symbol — o "L" de Lume como raio de luz
            sparkSymbol

            // 4. Specular highlight — reflexo superior esquerdo
            specularHighlight
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: s * 0.2237, style: .continuous))
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            // Base: preto-azulado profundo
            Color(red: 0.04, green: 0.04, blue: 0.08)

            // Radial glow — laranja quente no centro inferior
            RadialGradient(
                colors: [
                    Color(red: 0.95, green: 0.42, blue: 0.15).opacity(0.55),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.82),
                startRadius: 0,
                endRadius: s * 0.65
            )

            // Radial glow — violeta no canto superior direito
            RadialGradient(
                colors: [
                    Color(red: 0.55, green: 0.22, blue: 0.98).opacity(0.35),
                    Color.clear
                ],
                center: UnitPoint(x: 0.82, y: 0.15),
                startRadius: 0,
                endRadius: s * 0.5
            )

            // Radial glow — azul frio no canto superior esquerdo
            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.45, blue: 0.98).opacity(0.20),
                    Color.clear
                ],
                center: UnitPoint(x: 0.12, y: 0.08),
                startRadius: 0,
                endRadius: s * 0.4
            )
        }
    }

    // MARK: - Glass Orb

    private var glassOrb: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.55, blue: 0.18).opacity(0.45),
                            Color(red: 0.85, green: 0.28, blue: 0.75).opacity(0.25),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: s * 0.12,
                        endRadius: s * 0.42
                    )
                )
                .frame(width: s * 0.84, height: s * 0.84)
                .blur(radius: s * 0.04)

            // Glass sphere body
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color(red: 0.98, green: 0.55, blue: 0.18).opacity(0.28),
                            Color(red: 0.82, green: 0.22, blue: 0.72).opacity(0.22),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: UnitPoint(x: 0.25, y: 0.05),
                        endPoint: UnitPoint(x: 0.75, y: 0.95)
                    )
                )
                .frame(width: s * 0.58, height: s * 0.58)
                .overlay(
                    // Glass rim
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: UnitPoint(x: 0.2, y: 0.0),
                                endPoint: UnitPoint(x: 0.8, y: 1.0)
                            ),
                            lineWidth: s * 0.008
                        )
                )

            // Inner caustic — luz refratada no interior
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.12
                    )
                )
                .frame(width: s * 0.24, height: s * 0.18)
                .offset(x: -s * 0.06, y: -s * 0.10)
                .blur(radius: s * 0.015)
        }
        .offset(y: s * 0.02)
    }

    // MARK: - Spark Symbol

    // O símbolo é um "L" estilizado como raio/faísca —
    // representa Lume (luz) e inteligência elétrica.

    private var sparkSymbol: some View {
        ZStack {
            // Glow por baixo do símbolo
            Image(systemName: "sparkle")
                .resizable()
                .scaledToFit()
                .frame(width: s * 0.36, height: s * 0.36)
                .foregroundStyle(
                    Color(red: 1.0, green: 0.72, blue: 0.30)
                )
                .blur(radius: s * 0.06)

            // Símbolo principal — 4-pointed star (sparkle)
            Image(systemName: "sparkle")
                .resizable()
                .scaledToFit()
                .frame(width: s * 0.30, height: s * 0.30)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 1.0, green: 0.88, blue: 0.60),
                            Color(red: 1.0, green: 0.65, blue: 0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.60, blue: 0.15).opacity(0.9),
                        radius: s * 0.04, y: s * 0.01)

            // Pequena faísca secundária — canto superior direito
            Image(systemName: "sparkle")
                .resizable()
                .scaledToFit()
                .frame(width: s * 0.10, height: s * 0.10)
                .foregroundStyle(Color.white.opacity(0.75))
                .offset(x: s * 0.15, y: -s * 0.15)
                .blur(radius: s * 0.005)

            // Ponto brilhante — canto inferior esquerdo
            Circle()
                .fill(Color.white.opacity(0.50))
                .frame(width: s * 0.04, height: s * 0.04)
                .offset(x: -s * 0.16, y: s * 0.14)
                .blur(radius: s * 0.008)
        }
    }

    // MARK: - Specular Highlight

    private var specularHighlight: some View {
        ZStack {
            // Large soft highlight — topo
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.55, height: s * 0.22)
                .offset(y: -s * 0.38)
                .blur(radius: s * 0.018)

            // Tiny sharp specular — canto superior esquerdo
            Ellipse()
                .fill(Color.white.opacity(0.60))
                .frame(width: s * 0.08, height: s * 0.04)
                .offset(x: -s * 0.22, y: -s * 0.36)
                .blur(radius: s * 0.006)
                .rotationEffect(.degrees(-25))
        }
    }
}

// MARK: - Preview em múltiplos tamanhos

#Preview("1024pt") {
    AppIconView(size: 1024)
        .frame(width: 512, height: 512)
        .scaleEffect(0.5)
}

#Preview("256pt") {
    AppIconView(size: 256)
}

#Preview("64pt") {
    AppIconView(size: 64)
}

#Preview("32pt — Dock") {
    HStack(spacing: 20) {
        AppIconView(size: 32)
        AppIconView(size: 16)
    }
    .padding(20)
    .background(Color(white: 0.15))
}

#Preview("Grid — todos os tamanhos") {
    VStack(spacing: 24) {
        HStack(spacing: 20) {
            AppIconView(size: 1024).frame(width: 128, height: 128).scaleEffect(128/1024)
            AppIconView(size: 512).frame(width: 128, height: 128).scaleEffect(128/512)
            AppIconView(size: 256).frame(width: 128, height: 128).scaleEffect(0.5)
            AppIconView(size: 128)
        }
        HStack(spacing: 20) {
            AppIconView(size: 64)
            AppIconView(size: 32)
            AppIconView(size: 16)
        }
    }
    .padding(32)
    .background(
        LinearGradient(
            colors: [Color(white: 0.12), Color(white: 0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
