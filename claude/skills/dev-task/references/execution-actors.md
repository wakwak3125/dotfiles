# 実行主体切替

`dev-task` は Claude Code と Codex で同じ Skill ディレクトリを共有する。差分はこの reference に閉じ込め、`SKILL.md` と言語別 reference を二重管理しない。

## 最初に判定すること

- **Claude Code**: `EnterPlanMode` / `ExitPlanMode`、Agent / subagent、`CLAUDE_SKILL_DIR`、forge skill が使える実行環境。
- **Codex**: system/developer instruction で Codex として動作しており、`functions.update_plan`、`functions.apply_patch`、Browser plugin など Codex 側 tool を使う実行環境。
- 不明な場合は現在の harness で実際に使える tool に従う。存在しない tool 名を呼ぼうとしない。

## Context 方針

- 上流整理 (入力解決、受け入れ条件、影響範囲、類似実装の選定) は本体が持つ。
- 実装 worker / reviewer には、必要な作業仕様、対象ファイル、類似実装、検証コマンドだけを渡す。会話履歴全体を渡す前提にしない。
- reference は必要なものだけ読む。UI でなければ Figma / Storybook 系 reference は読まない。
- 大きいタスクは「調査結果の全文を本体 context に積む」のではなく、worker の最終出力を短い変更サマリ、変更ファイル、未解決事項、検証結果に圧縮して本体へ戻す。

## Skill ディレクトリ

Storybook スクショなど、Skill 配下のファイルを参照するときは `DEV_TASK_SKILL_DIR` を使う。

```bash
DEV_TASK_SKILL_DIR="${DEV_TASK_SKILL_DIR:-${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-$HOME/.codex/skills/dev-task}}}"
```

Claude Code では `CLAUDE_SKILL_DIR` があればそれを使う。Codex では dotfiles の bootstrap が `~/.codex/skills/dev-task` をこの共有 Skill へ symlink する前提。

## 進捗管理とプラン承認

### Claude Code

- PLAN_REQUIRED では `EnterPlanMode` に入り、`dev-task-planner` subagent を起動してプランだけを作らせる。
- 得られたプランは `ExitPlanMode` で提示し、承認 UI の明示承認を得てから実装へ進む。
- テキストで「承認しますか?」と聞くだけで代替しない。

### Codex

- 進捗が必要な規模では `functions.update_plan` を使う。
- PLAN_REQUIRED では、実装前に短いプランをユーザーに見せる。公開境界、DB / proto / API、横断的な責務配置など、誤ると戻しにくい判断がある場合は実装に進まず承認を待つ。
- ユーザーが「実装して」「直して」と明確に依頼し、期待挙動が一意で、リスクが局所的なら、Codex の通常方針に従ってプラン提示だけで止まらず実装まで進めてよい。

## 実装の担当

### Claude Code

- フェーズ 1〜3.5 はメインが担当する。
- 実装作業のデフォルトは Codex 委譲。`forge:codex-exec` を使い、forge を経由しない `codex exec` や codex subagent は使わない。
- メインが直接実装してよいのは、UI / 視覚調整、仕様が曖昧で対話しながら初稿を書く必要がある場合、Codex 委譲が 2 回で収束しない場合、または trivial 変更。
- 実装前に `担当: メイン / Codex、理由: ...` を 1 行で宣言する。
- Codex 委譲プロンプトには、課題、受け入れ条件、対象パス、類似実装パス、適用ルール、検証コマンドだけを書く。ペルソナ設定は書かない。

### Codex

- 小さい / 局所的な変更は Codex 本体が直接実装する。
- 非 trivial で context が肥大化しやすい実装は、ユーザーがサブエージェント / 委譲 / 並列エージェント作業を明示している場合に `multi_agent` の `worker` へ切り出す。
- 以下のような依頼文は委譲許可として扱う:
  - 「委譲ありで」
  - 「サブエージェントを使って」
  - 「実装とレビューはサブエージェントで」
  - 「並列エージェントで進めて」
- 実装前に `担当: Codex 本体 / Codex worker、理由: ...` を 1 行で宣言する。
- コード編集は Codex の通常ルールに従い、手作業の編集は `apply_patch` を使う。
- worker に実装を委譲する場合は、所有範囲 (ファイル / module / 責務) を明示し、他 worker や本体の変更を revert しないよう指示する。複数 worker を使う場合は write set を分ける。
- worker の prompt は自己完結させるが、`fork_context` は必要な場合だけ使う。基本は task facts だけを渡し、context コピーを避ける。
- UI 実装では Browser plugin / Playwright / 画像確認を使い、ユーザーが委譲を許可している場合は multi-agent review tool を独立レビューに使ってよい。使えない場合は、差分、スクショ、受け入れ条件を自分で構造化レビューする。

## 視覚比較

### Claude Code

- フェーズ 4g は `dev-task-visual-reviewer` subagent を起動し、実装者ではない第三者として判定させる。
- Figma 画像が欠けている場合は PASS 扱いにしない。

### Codex

- Figma 画像と Playwright スクショのペアを揃え、`view_image` や Browser screenshot で比較する。
- multi-agent tool が利用できるなら、比較画像ディレクトリ、対象 story、Figma semantic 要素リストを渡して独立レビューを依頼してよい。
- 独立 reviewer が使えない場合は、構造、余白、typography、色、state 差分を checklist 化して自己レビューする。判定不能な残差はユーザーに報告する。

## レビュー

### Claude Code

- trivial 以外は `dev-task-reviewer-correctness` と `dev-task-reviewer-style` を 1 メッセージ内で並列起動し、`forge:codex-review` も併用する。
- correctness には受け入れ条件と仮定、style には類似実装パスと公開境界の変更有無を渡す。
- must 相当の指摘は修正し、フェーズ 5 から再実行する。

### Codex

- trivial 以外は `git diff` をコードレビュー観点で読み直す。重大なバグ、境界条件、認可、例外処理、テスト不足、既存パターン逸脱を優先する。
- multi-agent review tool が使える場合は、correctness / style の観点を分けて独立レビューに使ってよい。
- reviewer が使えない場合でもレビューは省略せず、自己レビュー結果を must / imo に分けて処理する。
- must 相当の指摘は修正し、フェーズ 5 から再実行する。
