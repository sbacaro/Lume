//
//  SSEParser.swift
//  Lume
//
//  REMOVIDO — código morto. Os providers (OpenAI/Anthropic) consomem o stream SSE
//  diretamente via `URLSession.shared.bytes(for:)`, sem este parser. A classe antiga
//  (URLSessionDataDelegate com callbacks mutáveis) gerava warnings de Sendable sob
//  strict concurrency `complete`.
//
//  TODO: deletar este arquivo do projeto (Xcode navigator → Delete → Move to Trash).
//
