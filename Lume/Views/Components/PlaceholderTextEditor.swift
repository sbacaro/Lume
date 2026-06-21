//
//  PlaceholderTextEditor.swift
//  Lume
//

import SwiftUI

/// TextEditor com placeholder alinhado corretamente no macOS.
/// O NSTextView tem padding interno nativo de 5pt horizontal e 0pt vertical
/// quando textContainerInset é zero — mas o SwiftUI adiciona insets extras.
/// Esta view encapsula o alinhamento correto para uso em todo o projeto.
struct PlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var font: Font = .lume(.body)
    var minHeight: CGFloat = 36
    var maxHeight: CGFloat = 160
    var placeholderColor: Color = Color(.placeholderTextColor)
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // TextEditor sempre primeiro — define tamanho do ZStack
            TextEditor(text: $text)
                .font(font)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isFocused)

            // Placeholder com o mesmo offset interno do NSTextView
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(placeholderColor)
                    .allowsHitTesting(false)
                    // Alinhado com o início do texto/cursor do TextEditor.
                    // O texto real começa no topo do NSTextView; top=1 evita
                    // que o placeholder fique mais baixo que o cursor.
                    .padding(.top, 1)
                    .padding(.leading, 5)
            }
        }
    }
}
