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

依存関係のない subagent は 1 メッセージ内で並列起動する。

## Progress

進捗の可視化が必要なら Claude Code の Task tool (`TaskCreate` / `TaskUpdate`) を使ってよい。単純な作業では不要。

## Review

フェーズ 6 は SKILL.md の共通手順どおり、trivial でなければ Claude reviewer 2 体を基本とする。設計判断が重い変更では `references/codex-review.md` に従って codex-plugin-cc の companion を任意併用する。
