# 🎉 Lume v1.1.0 — Tela "Sobre", interface consistente e correções

Esta versão traz uma nova tela **Sobre o Lume**, um sistema unificado de botões nas
Configurações, correções de consistência no tema escuro e a eliminação de avisos de
concorrência do Swift 6.

**Data de lançamento:** 2026-06-15
**Versão:** v1.1.0 (build 3)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Tela "Sobre o Lume"
- Nova janela acessível pelo menu **Lume → Sobre o Lume**, no padrão de um app nativo do macOS
- Mostra o ícone do app, **versão e número de build**, descrição e requisitos técnicos
- Atalhos diretos para **Repositório no GitHub**, **Notas de versão**, **Reportar problema** e **Licença MIT**
- Botão **Verificar atualizações** com status ao vivo, integrado ao sistema de releases

### Interface mais consistente
- **Sistema único de botões** nas Configurações: estilos primário, secundário e destrutivo com a mesma forma, tamanho e comportamento em todas as abas e sheets — fim da mistura de cantos redondos/quadrados e tamanhos diferentes

---

## 🔧 Alterações

- A opção de **cor de acento** foi removida das Configurações; o app mantém apenas a escolha de **aparência** (Claro/Escuro/Sistema)

---

## 🐛 Correções

- **Tema escuro consistente:** a tela inicial do modo **Chat** herdava um fundo diferente do das telas **Cowork** e **Code**. Agora as três usam a mesma cor de fundo
- **Concorrência (Swift 6):** eliminados os avisos de mutação de variáveis capturadas em `ShellFunctions`, encapsulando o estado mutável num tipo de referência protegido por lock
- Removidos `await` redundantes em chamadas não-assíncronas (`AIProviderManager`, `AnthropicProvider`)

---

## 📦 Instalação

### Atualização automática
O app verifica novas versões pelo GitHub Releases. Quando houver atualização, basta
clicar em **Atualizar** na notificação (ou em **Verificar** na tela Sobre).

### Atualização manual
1. Baixe a versão mais recente em **GitHub Releases**
2. Arraste **Lume.app** para a pasta Aplicativos
3. Abra e aproveite

---

## 🖥️ Compatibilidade

- **macOS 14+** — binário universal (Intel / Apple Silicon)
- Totalmente retrocompatível com dados e configurações da v1.0.1

---

**Changelog completo:** veja [`CHANGELOG.md`](CHANGELOG.md) · [v1.1.0](https://github.com/sbacaro/Lume/releases/tag/v1.1.0)
