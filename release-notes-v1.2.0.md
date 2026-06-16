# 🌍 Lume v1.2.0 — Suporte a idiomas, botões em pílula e correções

Esta versão traz **internacionalização completa** (inglês + português do Brasil) com um
**seletor de idioma dentro do app**, a padronização de **todos os botões no formato pílula**
e a correção de um bug em que a chave de IA cadastrada no onboarding não aparecia em Configurações.

**Data de lançamento:** 2026-06-16
**Versão:** v1.2.0 (build 4)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Dois idiomas, do seu jeito
- Interface disponível em **inglês** e **português (Brasil)**, cobrindo toda a aplicação
- Novo **seletor de idioma** em **Configurações → Avançado → Idioma do App**: escolha **Sistema**, **English** ou **Português (Brasil)**; o app reinicia para aplicar
- Por padrão, o Lume agora **segue o idioma do macOS** (antes ficava preso em português)

### Interface mais consistente
- **Todos os botões em formato pílula (cápsula)** — o seletor Chat/Cowork/Code, o botão "Add" e as ações de diálogos agora têm a mesma forma

---

## 🔧 Alterações

- Base de código migrada para **inglês como idioma de origem**; as traduções em português passam pelo catálogo de strings, e não mais por textos fixos no código

---

## 🐞 Correções

- **Chave de IA do onboarding** (e do "Setup assistant") não se refletia em Configurações, exigindo novo cadastro — corrigido ao injetar o contexto de dados correto nos sheets
- Diversos textos antes fixos em português agora são corretamente localizáveis

---

## 📦 Instalação

### Atualização automática (Sparkle)
O app pode verificar automaticamente novas versões e instalar atualizações com um clique.

### Atualização manual
1. Baixe `Lume-1.2.0.dmg` abaixo
2. Arraste **Lume.app** para a pasta Aplicativos
3. Abra e aproveite

---

## 🖥️ Compatibilidade

- **macOS 14+** — binário universal (Intel / Apple Silicon)
- Totalmente retrocompatível com dados e configurações da v1.1.0

---

**Changelog completo:** veja [`CHANGELOG.md`](CHANGELOG.md)