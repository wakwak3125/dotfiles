---
name: dev-task-codex
description: Claude Code 専用。既存の dev-task workflow を壊さず、planner / reviewer / UI 実装は Claude Code、非 UI 実装だけ Codex CLI (`codex exec`) に bounded backend として同期委譲する dev-task wrapper Skill。「dev-task-codex で実装して」「Codex を implementer にしてこのチケットを進めて」「非 UI は Codex、UI は Claude で dev-task を回して」など、Claude Code から既存 dev-task 相当の実装を Codex backend 併用で行いたいときに使う。Codex からは使用しない。
---

# dev-task-codex

Claude Code で既存 `dev-task` workflow を実行しつつ、非 UI の実装だけ Codex CLI に委譲する wrapper Skill。

## 前提

- **Claude Code 専用。** Codex からこの Skill を使わない。repo の `agents/skills/manifest.tsv` でも `claude-code` のみに登録する。
- **既存 `dev-task` は変更しない。** この Skill は `dev-task` の上書きではなく wrapper。基本フェーズ、workspec、検証、レビュー、commit / push / draft PR は `dev-task` の規律に従う。
- **Codex は bounded implementer。** Codex に planner / reviewer / commit / push / PR / worktree 作成をさせない。Claude Code が orchestration と品質ゲートを持つ。
- **companion 風の job 管理はしない。** `status` / `result` / `resume` / background queue は不要。`codex exec` を 1 回同期実行し、戻った diff を Claude Code が確認する。

## Workflow

1. 既存 `dev-task` Skill を通常どおり使い、フェーズ 1〜3.5 で workspec、コンテキスト、必要ならプランを確定する。
2. フェーズ 4 の担当判断だけ、この Skill の [Routing](references/routing.md) を優先する。
3. Codex に委譲する場合は、[Codex Backend](references/codex-backend.md) に従って `codex exec` を同期実行する。
4. Codex が戻した後、Claude Code が `git diff` を読み、最小差分・既存パターン・公開境界を確認する。
5. フェーズ 5〜7 は既存 `dev-task` どおり Claude Code が実行する。trivial でなければ Claude reviewer を使う。

## Routing

詳細は `references/routing.md` を読む。

- planner: Claude Code の `dev-task-planner`
- non-UI implementer: Codex CLI backend
- UI / Figma / Storybook / visual adjustment: Claude Code main または既存 Claude implementer
- reviewer-correctness: Claude Code の `dev-task-reviewer-correctness`
- reviewer-style: Claude Code の `dev-task-reviewer-style`
- visual-reviewer: Claude Code の `dev-task-visual-reviewer`

## Model / Effort

詳細は `references/model-effort.md` を読む。

- 非 UI 通常 / 軽微実装: Codex `gpt-5.5`, `medium`
- 非 UI 高リスク実装: Codex `gpt-5.5`, `high`
- UI / visual / correctness review: Claude Opus, `high`
- style review: Claude Sonnet, `medium` を標準。大差分なら `high`

## Codex Invocation

Codex に渡す prompt は自己完結させる。最低限、以下を含める:

- workspec path
- 対象ファイル / 関数
- 類似実装 path
- 対象レイヤーの `dev-task` reference path
- allowed write scope
- 実行してよい検証コマンド
- 禁止事項: commit / push / PR / branch / worktree / scope 外編集 / dev-task workflow の再実行

`codex exec` の具体形と profile は `references/codex-backend.md` に従う。
