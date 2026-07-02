# dev-task バッチディスパッチ設計 (proposal)

複数チケットを一度に渡されたとき、dev-task が **1チケット1 worker** を再帰的に spawn し、メインは
ディスパッチとタスク管理・横断整合に専念してメイン context を新鮮に保つためのアーキテクチャ設計。

- ステータス: Phase A〜C 実装済み (並列 + 衝突事前検出 + 横断レビュー必須ゲート)。実バッチでの動作は未検証
- 前提: Claude Code v2.1.172 以降 (subagent のネスト spawn が可能)
- 関連: `agents/skills/dev-task/SKILL.md`、`agents/agents/dev-task-*.md`、`references/runtime-claude-code.md`

## 1. 目的

- **メイン context の鮮度維持** — チケットが何本あっても、メインには各 worker のコンパクトなサマリだけが返る。探索・実装・レビューの詳細は worker とその子で消費され、メインに漏れない。
- **タスク管理** — メインが全チケットの状態 (待ち / 進行 / 完了 / ブロック) を一元管理する。
- **横断整合** — 「単体では正しいが束ねると矛盾する」変更 (共有ファイル衝突・パターンのブレ・依存順序) をメインが検査する。

達成手段は「dev-task が dev-task を subagent として呼ぶ」再帰。v2.1.172 以降これは成立する
(トップレベル subagent のサマリだけがメインに返る仕様が、目的にそのまま合致する)。

## 2. 前提とネスト予算

Claude Code のネスト仕様 (`create-subagents` ドキュメント):

- subagent は自分の subagent を spawn できる。**深さ上限は 5** で固定・変更不可。深さ5の subagent は `Agent` tool を受け取らずそれ以上 spawn できない。
- ネストするには、その subagent の `tools` に **`Agent` を含める**必要がある (parens 内の型リストは無視される)。`Agent` を渡さなければ末端で止まる。
- **トップレベル subagent のサマリだけがメインに返る。** 中間サマリ (implementer → worker) は worker の context に留まる。
- 非 Explore/Plan subagent は CLAUDE.md と git status を毎回ロードする (worker ごとの固定コスト)。

本設計の深さ:

```
main (depth 0)  … ディスパッチャ
  └─ dev-task-worker (depth 1)  … 1チケットぶんの dev-task
        ├─ dev-task-planner     (depth 2)
        ├─ dev-task-implementer (depth 2)
        └─ dev-task-reviewer-*  (depth 2)
```

最大 depth 2 (Level 2 の subagent は `Agent` tool を持たないため末端)。上限 5 に対し余裕がある。visual-reviewer は使わない — Figma MCP とユーザー最終確認が必要な UI ユニットはバッチ対象外で、メインが直接処理する。

## 3. アーキテクチャ

3 層に責務を分割する。

| 層 | 主体 | 責務 |
|---|---|---|
| Level 0 | main (ディスパッチャ) | バッチ検知 / 依存グラフ / worker 割当 / タスク管理 / サマリ集約 / 横断整合 |
| Level 1 | `dev-task-worker` | 1チケットの dev-task フル実行 (理解〜実装〜検証〜レビュー〜PR)。隔離 context |
| Level 2 | `dev-task-planner` / `implementer` / `reviewer-*` | 既存 subagent をそのまま利用 |

メインは Level 1 のサマリしか読まない。単一チケット時は従来どおり (worker を挟まずメインが直接 dev-task を回す) で、バッチ時のみこの構成に切り替える。

## 4. `dev-task-worker` agent 定義 (新規)

1チケットぶんの dev-task を回すオーケストレータ。実質「1チケットのミニ main」。

frontmatter の要点:

```yaml
---
name: dev-task-worker
description: dev-task バッチ実行で 1 チケット/1 依頼を丸ごと担当する worker。理解〜設計〜実装〜検証〜レビュー〜PR を隔離 context で完遂し、コンパクトなサマリを返す。
tools: Read, Grep, Glob, Edit, Write, Bash, Agent, Skill  # Agent 必須 (Level 2 を spawn するため)
model: inherit          # 難易度はセッションモデルに追従 (planner と同じ思想)
isolation: worktree     # 各 worker に隔離されたリポジトリ複製を与え、並列編集衝突を根本回避
skills: [dev-task]      # dev-task の手順をプリロード (or Skill tool で起動)
---
```

- **`Agent` 必須** — これが無いと Level 2 (implementer/reviewer 等) を spawn できず、全部インライン実行に退化する。
- **`isolation: worktree`** — 並列 worker が同一作業ツリーで衝突するのを防ぐ最重要ポイント。デフォルトブランチから分岐した隔離コピーで作業する**前提** (基点仕様は未検証のため、worker が作業開始時に `git merge-base --is-ancestor` で確認し、想定外ならブロック報告する)。
- **MCP ツールは持たない** — Linear チケット内容はディスパッチャが取得して作業仕様で渡す。Figma MCP が要る UI ユニットはバッチ対象外 (メインが直接処理)。
- **`model: inherit`** — worker は理解・トリアージ・オーケストレーションを担う。難易度が出る工程なので、確立済みモデル方針 (planner=inherit、実行/レビュー=opus/high) に合わせて worker も inherit。worker が spawn する planner も inherit のままセッションモデルに解決される。
- 役割は SKILL.md のフェーズ 1〜7 をそのまま 1 チケットに適用し、**メインへ返すのはサマリのみ** (下記フォーマット)。

worker が返すサマリ (メインの集約・横断整合の入力):

```
## worker 結果: <ticket-id / タスク名>
- 状態: 完了 / ブロック(理由)
- ブランチ / worktree パス
- PR URL (作成時)
- 変更ファイル一覧 (パスのみ)
- 検証結果 (型/ビルド/テスト/lint の pass/fail)
- 置いた仮定
- 横断メモ: 触れた公開境界 / 共有ファイル / 新規パターン (メインの整合検査用に必須)
```

## 5. フェーズ 0: バッチ検知・ディスパッチ (SKILL.md に追加)

単一入力時は発火しない。以下のいずれかで **バッチモード**に入る:

- 複数のチケット ID が渡された (`[A-Z]+-\d+` が 2 件以上)
- チケット/タスクのリストが渡された
- ユーザーが「まとめて」「これら全部」等でバッチを明示

いずれも候補シグナルで、参照のみの ID (「〜と同じパターンで」等) を除外して**独立した作業依頼が 2 件以上と確認できた場合のみ**発火する (判定手順は SKILL.md フェーズ 0)。

手順:

1. **入力分解** — 各チケット/タスクを 1 ユニットに正規化し、TaskCreate でタスク登録。Linear チケットはメインが本文・コメントを取得して作業仕様に含める (worker は MCP を持たない)。UI ユニット (Figma 起点) はバッチから分離しメインが直接処理。
2. **依存グラフ構築** — ユニット間の依存を判定する。
   - **入力が Linear チケットのときは Linear の関係を第一情報源にする** (Linear 依存モード)。チケット取得時に `blocks` / `blocked by` / `parent` / `sub-issue` も取り、`blocked by` チェーンを依存辺とする。Linear が真実、コード推測 (proto→利用側、共有ライブラリ→利用側 等) は補助。
   - 自然言語ユニットや Linear 関係が無い場合はコード推測のみ。曖昧なら依存ありに倒す。
   - 依存があるものは blocker マージ後に blocked を流す (未マージならユーザー判断)、独立は並列候補。
3. **共有ファイル衝突の事前検出** — 各ユニットが触りそうなファイルを軽く見積もり、重なるユニットは並列にしない。worker は常にデフォルトブランチ基点のため直列起動だけではマージ衝突は解消せず、依存チェーンと同じく先行の PR マージ後に流すかユーザーに判断を仰ぐ。
4. **共通コンテキストの用意** — 全 worker に渡す共有 workspec (リポジトリ規約・命名・依存関係・スコープ境界)。パターンのブレを防ぐ。
5. **スケジューリング & 並列ディスパッチ** — 依存・衝突グループの制約を満たす独立ユニットを並列度上限 (既定値は SKILL.md フェーズ 0 手順 5 で定義) まで並列 spawn。上限超過はキュー。
6. **サマリ集約** — 各 worker のサマリを TaskUpdate に反映。
7. **横断レビュー (必須ゲート)** — 全 worker 完了後、サマリの横断メモを突き合わせ、公開境界の二重変更・共有ファイルの論理衝突・パターン乖離・重複実装を必ず検査。問題は該当 worker に再委譲 (最大 2 回)。再委譲は既存 push 済みブランチの再開として渡す (worker が `git fetch` + `git switch` で再開)。

## 6. 難所と対処

ネストが可能でも自動では解決しない、本設計の実質的な難所。

1. **依存順序** — 依存ユニットは直列。判定を誤ると後段が古い前提で実装する。**Linear チケット入力なら Linear 関係を第一情報源に**し、それ以外はコード推測で保守的に (曖昧なら直列) 倒す。なお blocked ユニットは worker がデフォルトブランチ基点で worktree を切るため、blocker マージ後に流すのが前提 (blocker ブランチを base にする自動化はスコープ外)。
2. **共有ファイル衝突** — `isolation: worktree` で編集は隔離できるが、**最終マージ**で衝突する。事前の重なり検出 (フェーズ0-3) と「先行の PR マージ後に後続を流す」ゲートで回避 (直列起動だけでは解消しない)。検出漏れは横断レビュー (0-7) で拾う。
3. **パターン整合** — 共有 workspec (0-4) を全 worker に渡し、同一の参照パターン・規約を強制する。
4. **集約と横断レビュー** — 単体 PASS でも束ねると矛盾する系。横断メモを必須項目にして、メインが必ず突き合わせる。
5. **並列度の上限** — worker を無制限並列にすると、サマリ返却でメイン context も太る & リソース逼迫。上限を設け (既定値は SKILL.md フェーズ 0 手順 5 で一元定義)、超過分はキュー。上限は要チューニング。
6. **エスカレーション** — あるユニットがブロックしたとき、独立ユニットは続行、依存ユニットは停止してユーザーに提示。

## 7. モデル / 深さ / 並列度の方針

- **model**: worker=inherit、Level 2 は既存方針 (planner=inherit、implementer/reviewer/visual=opus/high)。難易度対応はメインのセッションモデル切替に一本化される。
- **depth**: 最大 2 (上限 5)。将来 worker-in-worker (バッチの中のバッチ) はやらない — 深さと複雑性が跳ねる。
- **並列度**: 既定値は SKILL.md フェーズ 0 手順 5 で一元定義 (現在 4)。サマリ肥大とメイン context のトレードオフを見て調整。

## 8. 段階的ロールアウト

1. **Phase A (実装済み)** — `dev-task-worker` 定義 + SKILL.md フェーズ0 の骨格。再帰 spawn と context 隔離。
2. **Phase B (実装済み)** — 独立ユニットの並列化 (`isolation: worktree` + 並列度上限)。
3. **Phase C (実装済み, 最終)** — 共有ファイル衝突の事前検出 (touch-set 見積もり → 並列回避 + 先行マージ待ちゲート) と横断レビューの必須ゲート化。

Phase C までがスコープ。依存グラフのさらなる精緻化 (proto/生成コード等の型別ルール) や、未マージ blocker のブランチを base にして依存ユニットを先行実装する自動化は**スコープ外**とする (依存チェーンは「blocker マージ後に blocked」の直列運用で足りるとの判断)。

残りは実バッチでの動作検証 (再帰 spawn・context 隔離・isolation worktree のブランチ運用・並列度) と、検証結果を踏まえた並列度・衝突検出ヒューリスティックの調整。

## 9. 意思決定 (確定) と残課題

確定:

- **worker への手順の渡し方**: `skills: [dev-task]` プリロード。
- **単一/バッチの分岐点**: 独立した作業依頼が 2 件以上で自動バッチ (参照のみのチケット ID はユニットにしない)。
- **並列度のデフォルト**: 4 (超過はキュー)。規範値の定義箇所は SKILL.md フェーズ 0 手順 5 に一元化。
- **worker のモデル/隔離**: `model: inherit` + `isolation: worktree`。
- **PR 粒度**: ユニットごとに個別 draft PR (worker がフェーズ 7 で作成)。

残課題 (実測後に調整):

- 並列度既定値と衝突検出ヒューリスティックの妥当性を実バッチで検証。
- 自動バッチの誤発火 (参照 ID の作業依頼への誤判定) のコスト観察。
- worktree の後始末 (マージ後の `git wtclean` 連携)。
- isolation worktree の基点 (デフォルトブランチ分岐か) を実バッチで確認。worker 側の `git merge-base --is-ancestor` チェックはその防御。
