# Model And Effort

品質とコストの標準配分。

| 役割 | 実行主体 | モデル | effort |
| --- | --- | --- | --- |
| main / orchestrator | Claude Code | inherit | inherit |
| `dev-task-worker` | Claude | sonnet | high |
| `dev-task-planner` | Claude | inherit | high |
| 非 UI 通常実装 | Codex | gpt-5.4 | high |
| 非 UI 軽微修正 | Codex | gpt-5.4-mini | medium |
| 非 UI 高リスク実装 | Codex | gpt-5.5 | high |
| UI / Figma / visual 実装 | Claude | opus | high |
| `dev-task-visual-reviewer` | Claude | opus | high |
| `dev-task-reviewer-correctness` | Claude | opus | high |
| `dev-task-reviewer-style` | Claude | sonnet | medium |
| Codex review 併用 | Codex | gpt-5.5 | high |

## High Risk

次に該当する非 UI 実装は heavy profile を使う。

- 公開境界: HTTP API / proto / DB / export 型 / event payload
- 認可、transaction、並行性、冪等性
- PLAN_REQUIRED だったタスク
- 影響範囲が複数レイヤーにまたがる変更

## Fast Path

次に該当するものは fast profile でよい。

- import 整理
- lint / format の明確な修正
- 型エラーの局所修正
- 単純な定数・文言・設定値の差し替え
- テスト名や fixture の小修正

## Reviewer

Codex 実装後の reviewer は Claude に寄せる。特に correctness review は Opus high を維持する。

style review は Sonnet medium を標準にし、公開境界や大差分を含む場合だけ high に上げる。
