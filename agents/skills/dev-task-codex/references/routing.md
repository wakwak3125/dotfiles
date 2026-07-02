# Routing

`dev-task-codex` は既存 `dev-task` の wrapper として、フェーズ 4 の担当判断だけを差し替える。

## 基本ルーティング

| 領域 | 担当 | 理由 |
| --- | --- | --- |
| 仕様解決 / workspec / トリアージ | Claude Code main | ユーザー対話と判断の責任を持つため |
| PLAN_REQUIRED の plan | Claude `dev-task-planner` | 設計判断を Claude 側で固定してから Codex に渡すため |
| 非 UI 実装 | Codex CLI backend | 実装コストを下げつつ、diff は Claude が検査できるため |
| UI / Figma / Storybook / visual adjustment | Claude Code | Figma MCP、スクショ確認、視覚反復は Claude orchestration が必要なため |
| 検証失敗の機械修正 | 原則、直前の実装担当 | Codex 実装なら Codex に 1 回戻す。UI は Claude が直す |
| correctness review | Claude reviewer | Codex 実装から独立したレビューにするため |
| style review | Claude reviewer | 既存 dev-task 規律の確認を Claude 側に残すため |
| commit / push / draft PR | Claude Code main | 最終責任と GitHub 操作を main に集約するため |

## Codex に委譲する条件

次をすべて満たすとき、Codex backend に委譲する。

- UI / Figma / Storybook / visual adjustment ではない
- workspec と受け入れ条件が確定している
- 対象ファイル、類似実装、allowed write scope を渡せる
- Codex が approval なしで失敗しても Claude Code が復旧判断できる

## Claude が実装する条件

次のいずれかに当たる場合は Codex に委譲しない。

- Figma URL、Storybook、Playwright screenshot、視覚差分が主目的
- 仕様が探索的で、実装しながらユーザー判断が必要
- allowed write scope を安全に切れない
- Codex backend が利用不可、または `codex exec` が起動に失敗する
- Codex への再依頼が 2 回で収束しない

## Codex review の扱い

Codex が実装した diff に Codex review を足しても独立性が弱い。通常は Claude reviewer 2 系統で十分。

Codex review を併用するのは、Claude が実装した高リスク変更を独立エンジンで見たい場合に限る。
