#!/bin/bash
# Rodar este script com o Xcode FECHADO
# cd ~/Desktop/Lume/Lume && bash push_to_github.sh

set -e

echo "==> Resetando staging area..."
git rm --cached -r . -f 2>/dev/null || true

echo "==> Removendo arquivos duplicados do disco (se ainda existirem)..."
rm -f "Localizable 2.xcstrings"
rm -f "Lume/ContentView 2.swift"
rm -f "Lume/Lume 2.entitlements"

echo "==> Removendo xcuserdata do tracking..."
git rm --cached -r Lume.xcodeproj/xcuserdata/ 2>/dev/null || true

echo "==> Adicionando todos os arquivos..."
git add .

echo "==> Commitando..."
git commit -m "feat: versão 1.0.0 — cliente nativo de IA para macOS"

echo "==> Configurando remote..."
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/sbacaro/Lume.git

echo "==> Fazendo push..."
git push -u origin main

echo ""
echo "✅ Pronto! Acesse: https://github.com/sbacaro/Lume"
