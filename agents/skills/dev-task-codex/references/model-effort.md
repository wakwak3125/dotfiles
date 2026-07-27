# Model And Effort

品質とコストの標準配分。**Claude 側 subagent の model / effort は `agents/agents/dev-task-*.md` の frontmatter が唯一の真実** (方針は dev-task 本体の `references/runtime-claude-code.md` を参照)。この文書で規定するのは Codex 側だけ:

| 役割 | 実行主体 | モデル | effort |
| --- | --- | --- | --- |
| main / orchestrator | Claude Code | inherit | inherit |
| Claude subagent (planner / implementer / reviewer / visual / worker) | Claude | frontmatter に従う | frontmatter に従う |
| 非 UI 通常 / 軽微実装 | Codex | gpt-5.6-sol | medium |
| 非 UI 高リスク実装 | Codex | gpt-5.6-sol | high |
| Codex review 併用 | Codex | gpt-5.6-sol | high |

## High Risk

次に該当する非 UI 実装は heavy profile を使う。

- 公開境界: HTTP API / proto / DB / export 型 / event payload
- 認可、transaction、並行性、冪等性
- PLAN_REQUIRED だったタスク
- 影響範囲が複数レイヤーにまたがる変更

## Fast Path

次に該当するものは通常 profile (`dev-task-implementer`) でよい。

- import 整理
- lint / format の明確な修正
- 型エラーの局所修正
- 単純な定数・文言・設定値の差し替え
- テスト名や fixture の小修正

## Reviewer

Codex 実装後の reviewer は Claude に寄せる。model / effort は各 reviewer の frontmatter に従う (correctness は Opus high、style は Opus medium が現行値)。
