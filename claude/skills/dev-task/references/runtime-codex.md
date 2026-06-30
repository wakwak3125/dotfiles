# Codex runtime adapter

dev-task を Codex で実行するときのホスト固有ルール。SKILL.md の共通ワークフローに Claude Code 専用の記述が残っている場合、この adapter を優先する。

## Skill directory

`CLAUDE_SKILL_DIR` は使わない。スクリプトや reference を実行する前に、dev-task の Skill ディレクトリを `DEV_TASK_SKILL_DIR` として扱う。

候補:

- user scope: `$HOME/.codex/skills/dev-task`
- project scope: `<repo>/.agents/skills/dev-task`
- `gh skill install --agent codex --scope user` で表示された install path

コマンド例:

```bash
export DEV_TASK_SKILL_DIR="$HOME/.codex/skills/dev-task"
```

## Plan creation

Claude Code の `EnterPlanMode` / `ExitPlanMode` は使わない。

PLAN_REQUIRED でも、実装前に plan をユーザーへ提示して承認を待つことはしない。プランを作成して workspec に記録したら、そのままフェーズ 4 へ進む。Codex の `update_plan` は進捗管理に使ってよい。ユーザーがすでに承認済みプランを渡した場合は、共通手順どおりフェーズ 4 から進める。

## Delegation

Claude Code の `Agent` tool と `claude/agents/dev-task-*.md` は前提にしない。Codex ではメインエージェントが原則として実装・検証・レビュー統合まで担当する。

利用可能な multi-agent tools があり、作業の分離が明確で、追加の承認や外部状態変更を増やさない場合だけ、探索・実装・レビューの一部を subagent に委譲してよい。使えない場合は止まらずメインで進める。

## Progress

進捗の可視化が必要なら Codex の `update_plan` を使う。作業中のユーザー更新、編集前の説明、検証結果の報告は Codex の通常ルールに従う。

## Review

フェーズ 6 では Claude reviewer subagent を起動しない。trivial でなければ、メインエージェントが code-review stance で `git diff` を読み、以下を分けて確認する:

- correctness: 正確性、境界条件、型安全性、セキュリティ、テスト不足
- style: 既存パターン整合、最小差分、公開境界不変、命名、コメント方針

Codex 自身が実行主体なので `references/codex-review.md` の codex-plugin-cc companion は使わない。独立レビューが必要で multi-agent tools も使えない場合は、最終報告に「独立 reviewer は未実行」と明記する。

## UI and visual checks

Figma / Playwright / Storybook の共通手順はそのまま使う。Figma 操作は Codex 側で利用可能な Figma skill / MCP / connector に従う。画像比較では必要に応じてローカル画像ビューアや Playwright screenshot を使い、`__playwright.png` と `__figma.png` のペア必須条件は緩めない。

スクリプト実行は `${DEV_TASK_SKILL_DIR}` を使う:

```bash
node "${DEV_TASK_SKILL_DIR}/scripts/screenshot-stories.mjs"
node "${DEV_TASK_SKILL_DIR}/scripts/diff-pairs.mjs"
```

## Git and PR

コミット、push、draft PR は SKILL.md の共通手順と Codex の開発者指示の両方に従う。破壊的操作や外部書き込みが必要なコマンドは Codex の承認ルールを優先する。
