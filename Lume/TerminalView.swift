//
//  TerminalView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI

struct TerminalView: View {
    @State private var terminal = TerminalSession()
    @State private var inputText = ""
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @FocusState private var inputFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            outputArea
            Divider()
            inputArea
        }
        .background(Color.black)
        .onAppear { inputFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .terminalNeedsPassword)) { notif in
            guard (notif.object as? TerminalSession) === terminal else { return }
            passwordInput = ""
            showPasswordPrompt = true
        }
        .sheet(isPresented: $showPasswordPrompt) {
            passwordSheet
        }
    }

    // MARK: - Password Sheet

    private var passwordSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Autenticação de Administrador")
                .font(.system(size: 15, weight: .semibold))

            Text("Digite sua senha para executar comandos com privilégios elevados.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("Senha", text: $passwordInput)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit { submitPassword() }

            HStack(spacing: 12) {
                Button("Cancelar", role: .cancel) {
                    showPasswordPrompt = false
                    terminal.submitPassword(nil)
                }

                Button("Autenticar") {
                    submitPassword()
                }
                .buttonStyle(.borderedProminent)
                .disabled(passwordInput.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { passwordFocused = true }
    }

    private func submitPassword() {
        let pwd = passwordInput
        passwordInput = ""
        showPasswordPrompt = false
        terminal.submitPassword(pwd)
    }

    // MARK: - Output area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(terminal.lines) { line in
                        TerminalLineView(line: line)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .onChange(of: terminal.lines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Input area

    private var inputArea: some View {
        HStack(spacing: 8) {
            Text(promptString)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(promptColor)

            TextField("", text: $inputText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit { submitCommand() }
                .onKeyPress(.upArrow) {
                    inputText = terminal.previousCommand() ?? inputText
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    inputText = terminal.nextCommand() ?? inputText
                    return .handled
                }
                .onKeyPress(.tab) {
                    inputText = terminal.autocomplete(inputText)
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }

    // MARK: - Computed

    private var promptString: String {
        let dir = URL(fileURLWithPath: terminal.workingDirectory).lastPathComponent
        return terminal.isSudoSession ? "root@lume \(dir) # " : "lume \(dir) $ "
    }

    private var promptColor: Color {
        terminal.isSudoSession ? .orange : .green
    }

    private func submitCommand() {
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        inputText = ""
        Task { await terminal.execute(cmd) }
    }
}

// MARK: - Terminal Line View

struct TerminalLineView: View {
    let line: TerminalLine

    var body: some View {
        Text(line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(lineColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineColor: Color {
        switch line.type {
        case .command: return .white.opacity(0.9)
        case .output:  return .white.opacity(0.75)
        case .error:   return Color(red: 1, green: 0.4, blue: 0.4)
        case .system:  return Color(red: 0.4, green: 0.8, blue: 1)
        case .sudo:    return Color(red: 1, green: 0.7, blue: 0.2)
        }
    }
}
