# MTG 決定事項集約

> `spec-planner` が MTG 議事録（ローカル or Google Docs）と `base:` 文書、自然文の指示を取り込んで正規化するファイル。
> 設計用 subagent（analyst / architect / modeler / critic）はこのファイルを一次情報として読む。
> Gemini トランスクリプトや Google Docs 本文を**逐語転記しない**。決定と論点だけを抽出する。

## Sources

> 取り込み元の一覧。後から追加した場合も末尾に追記する。

| # | 種別 | 参照 | 取り込み方法 | 日時（推定） |
|---|------|-----|-------------|--------------|
| 1 | local-md | `./minutes/2026-05-10.md` | Read | 2026-05-10 14:00 |
| 2 | gdoc | `https://docs.google.com/document/d/abc123/edit` | mcp-read-file-content | 2026-05-13 10:30 |

## Decisions Timeline

> MTG 日時の昇順。各 MTG ごとに 1 セクション。決定事項は箇条書き、論点・経緯は最小限。

### 2026-05-10 <MTG タイトル>

**参加者（推定）**: ...

**主要決定事項**:

- D-M{YYYYMMDD}-001: ...
  - 経緯: ...
- D-M{YYYYMMDD}-002: ...

**保留 / 持ち越し**:

- ...

### 2026-05-13 <MTG タイトル>

**主要決定事項**:

- D-M{YYYYMMDD}-001: ...

## Overridden Decisions

> 新しい MTG が古い決定を覆した場合に記録する。無ければ「該当なし」。

| 覆された決定 ID | 覆した決定 ID | 経緯 |
|----------------|--------------|------|
| D-M20260510-001 | D-M20260513-002 | 返金プロバイダ変更により... |

## Base Documents

> `base:` で渡された既存の要求・要件・設計文書。subagent には offset/limit で参照可。

| パス | 役割 | 冒頭抜粋 |
|------|------|----------|
| `./docs/requirements.md` | 要求仕様 | ... |

## Ad-hoc Instructions

> `$ARGUMENTS` の自然文指示本文（slug/meetings/base キーを除いた残り）を全文転記する。subagent はこれを「ユーザーの直近の意図」として最優先で扱う。

<!-- ここに $ARGUMENTS の指示本文を転記 -->
