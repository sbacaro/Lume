//
//  StreamingIndicatorView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import Combine

/// Indicador de "digitando" — três pontos pulsantes estilo iMessage.
/// Mostrado abaixo da última mensagem do assistente enquanto isStreaming = true
/// e o conteúdo ainda está vazio (antes do primeiro chunk chegar).
struct StreamingIndicatorView: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(phase == i ? 0.9 : 0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

/// Mostra tokens/s durante o streaming — útil para debug e feedback visual.
struct StreamingStatsView: View {
    let tokenCount: Int
    let elapsed: TimeInterval

    private var tokensPerSecond: Double {
        guard elapsed > 0 else { return 0 }
        return Double(tokenCount) / elapsed
    }

    var body: some View {
        if tokenCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                Text("\(Int(tokensPerSecond)) tok/s · \(tokenCount) tokens")
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .transition(.opacity)
        }
    }
}
