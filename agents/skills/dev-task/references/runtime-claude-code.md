# Claude Code runtime adapter

dev-task を Claude Code で実行するときのホスト固有ルール。SKILL.md の共通ワークフローをこの adapter で解釈する。

## Skill directory

`DEV_TASK_SKILL_DIR` は `CLAUDE_SKILL_DIR` と同じ値として扱う。スクリプトや reference の絶対パスを渡すときは次を前提にする:

```bash
export DEV_TASK_SKILL_DIR="${CLAUDE_SKILL_DIR:?}"
```

以降、共通手順内の `${DEV_TASK_SKILL_DIR}` は Claude Code が設定する Skill ディレクトリを指す。

## Plan creation

PLAN_REQUIRED でも plan mode (`EnterPlanMode` / `ExitPlanMode`) は使わず、人間の承認は取らない:

1. `dev-task-planner` subagent を `Agent` tool で起動する。
2. 返ってきたプランを workspec に追記し、そのままフェーズ 4 へ進む。

`ExitPlanMode` 等の承認 UI で実装開始の許可を待たない。ただしユーザーが自分から plan mode で承認したプランを渡してきた場合は、SKILL.md の *承認済みプランからのエントリ* に従いフェーズ 4 から進める。

## Delegation

実装・レビュー・視覚比較の委譲は Claude Code の `Agent` tool と `agents/agents/dev-task-*.md` を使う。

- 実装: `dev-task-implementer`
- 計画: `dev-task-planner`
- 正確性レビュー: `dev-task-reviewer-correctness`
- スタイルレビュー: `dev-task-reviewer-style`
- 視覚比較: `dev-task-visual-reviewer`
- バッチ 1 ユニット担当 (フェーズ 0): `dev-task-worker`

依存関係のない subagent は 1 メッセージ内で並列起動する。

### バッチ (フェーズ 0) のネスト

複数ユニット時、メインは各ユニットを `dev-task-worker` に委譲する (SKILL.md フェーズ 0)。worker は `tools` に `Agent` を持ち、内部で Level 2 subagent (planner / implementer / reviewer / visual) を通常どおり spawn する。深さは main(0) → worker(1) → Level 2(2) で、Claude Code のネスト上限 5 に十分収まる。**トップレベル (worker) のサマリだけがメインに返る**ため、メイン context は各ユニットのサマリのみで済む。

- **並列**: 依存・衝突グループの制約を満たす独立ユニットを、並列度上限 (既定 4) まで 1 メッセージ内で並列 spawn する。上限超過はキュー。
- **隔離**: worker は `isolation: worktree` で隔離実行されるため、並列でもファイルレベルで衝突しない。最終マージで衝突しうるユニット (touch-set が重なる) はフェーズ 0 手順 3 で事前に直列グループ化する。

### Model / effort 方針

各 `agents/agents/dev-task-*.md` の frontmatter が唯一の真実。方針は以下:

- **実行・レビュー系 (`implementer` / `reviewer-correctness` / `reviewer-style` / `visual-reviewer`) は `opus` + `effort: high` に固定。** タスクの難易度によらず、実装・レビュー品質を一定に保つ。
- **`planner` だけ `model: inherit` (effort もセッション追従)。** 設計・計画は難易度が最も出る工程なので、セッションのモデル (難タスクは Fable、通常タスクは Opus 等) と effort をそのまま引き継ぐ。

結果として、難易度への対応はメインが**セッションのモデルを切り替えるだけ**で済む。planner がそれに追従し、実行・レビューは Opus 4.8 / high の一定品質が保たれる。

## Progress

進捗の可視化が必要なら Claude Code の Task tool (`TaskCreate` / `TaskUpdate`) を使ってよい。単純な作業では不要。

## Review

フェーズ 6 は SKILL.md の共通手順どおり、trivial でなければ Claude reviewer 2 体を基本とする。設計判断が重い変更では `references/codex-review.md` に従って codex-plugin-cc の companion を任意併用する。
