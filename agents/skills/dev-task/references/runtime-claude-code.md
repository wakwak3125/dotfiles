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

- 実装 (高リスク): `dev-task-implementer`
- 実装 (通常・軽微): `dev-task-implementer-light` — profile の選択基準は下記 *Model / effort 方針*
- 計画: `dev-task-planner`
- 正確性レビュー: `dev-task-reviewer-correctness`
- スタイルレビュー: `dev-task-reviewer-style`
- 視覚比較: `dev-task-visual-reviewer`
- バッチ 1 ユニット担当 (フェーズ 0): `dev-task-worker`

依存関係のない subagent は 1 メッセージ内で並列起動する。

### バッチ (フェーズ 0) のネスト

複数ユニット時、メインは各ユニットを `dev-task-worker` に委譲する (SKILL.md フェーズ 0)。worker は `tools` に `Agent` を持ち、内部で Level 2 subagent (planner / implementer / reviewer) を通常どおり spawn する (UI ユニットはバッチ対象外のため visual-reviewer は使わない)。深さは main(0) → worker(1) → Level 2(2) で、Claude Code のネスト上限 5 に十分収まる。**トップレベル (worker) のサマリだけがメインに返る**ため、メイン context は各ユニットのサマリのみで済む。

- **並列**: 依存・衝突グループの制約を満たす独立ユニットを、並列度上限 (既定値の定義は SKILL.md フェーズ 0 手順 5) まで 1 メッセージ内で並列 spawn する。上限超過はキュー。
- **隔離**: worker は `isolation: worktree` で隔離実行されるため、並列でもファイルレベルで衝突しない。最終マージで衝突しうるユニット (touch-set が重なる) はフェーズ 0 手順 3 に従い並列にせず、先行ユニットのマージ後に流すかユーザー判断に委ねる (直列起動だけではマージ衝突は解消しない)。

### Model / effort 方針

各 `agents/agents/dev-task-*.md` の frontmatter が唯一の真実。役割ごとの配分: 設計・計画は Fable 5、実装・レビューは Opus 5 (effort はリスクで自動切り替え)。

- **`planner` は `model: fable` に固定。** 設計・計画は難易度が最も出る工程なので最上位モデルに任せる (PLAN_REQUIRED のときしか起動しないためコスト影響は限定的)。`fable` が使えない環境でエラーになる場合は `model: inherit` に戻す。
- **実装は Opus 5 の 2 profile を使い分ける (effort の自動切り替え)。** `Agent` tool は spawn 時に model は上書きできるが effort は上書きできないため、effort 違いの定義を 2 つ持ち、メインが差分の性質で選ぶ:
  - `dev-task-implementer` (`opus` + `high`) — **高リスク実装**: 公開境界 (HTTP API / proto / DB / export 型 / event payload) に触れる、認可・トランザクション・並行性・冪等性、PLAN_REQUIRED だったタスク、複数レイヤー横断
  - `dev-task-implementer-light` (`opus` + `medium`) — **上記以外の通常・軽微実装**: 局所的な機能追加・bug fix・テスト追加・import 整理・lint / 型エラーの機械修正・定数 / 文言 / 設定値の差し替え
  - 迷ったら high 側 (`dev-task-implementer`)。フェーズ 5 の検証失敗の修正ループは初回実装と同じ profile に続けさせる。2 つの定義の本文は同一に保つ (分岐は frontmatter のみ)。
- **reviewer は静的に固定。** `reviewer-correctness` / `visual-reviewer` は `opus` + `high` (品質ゲートの最後の砦)。`reviewer-style` は `opus` + `medium` (Opus 5 はレビュー精度が低 effort でも維持され、スタイル整合は高 effort の恩恵が小さい)。
- **`worker` は `model: inherit`。** バッチの 1 ユニットを丸ごと持つ「ミニ main」なのでセッションに追従する。

セッションを Fable で走らせると、メイン (オーケストレーション) と planner が Fable 5、実装・レビューが Opus 5 という配分になる。

## Progress

進捗の可視化が必要なら Claude Code の Task tool (`TaskCreate` / `TaskUpdate`) を使ってよい。単純な作業では不要。

## Review

フェーズ 6 は SKILL.md の共通手順どおり、trivial でなければ Claude reviewer 2 体を基本とする。設計判断が重い変更では `references/codex-review.md` に従って codex-plugin-cc の companion を任意併用する。
