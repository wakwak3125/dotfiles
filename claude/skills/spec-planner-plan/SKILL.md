---
name: spec-planner-plan
description: 要求仕様を入力として、architect / modeler / requirements-analyst / critic / scribe の 5 人 subagent チームで高度なソフトウェア設計レビュー＆改訂を行う。critic の重大指摘が尽きるまでラウンドを動的に回す。成果物は設計書（design.md）・データモデル（data-model.md：ER図＋テーブル定義）・要求対応表・ユースケースごとのデータ構造・残タスク・議事録・改訂履歴。設計の検討・設計レビュー・仕様策定の議論を深めたいときに使う。
argument-hint: <設計対象のコンテキストと任意のチーム構成>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskList, TaskUpdate, TaskGet
---

# spec-planner-plan: 要求 → 設計 を 5 人チームで鍛えるスキル

あなたはこのスキルのファシリテーター（エージェントチームの**リーダー**）として動く。
入力から設計対象を読み取り、subagent 定義に基づく agent team を編成し、
5〜10 ラウンドの批判的議論と改訂を経て成果物を仕上げる。

## 入力

`$ARGUMENTS` には以下が含まれる:
- **何についての設計か**（必須）: 対象システム・機能の説明、既存コード参照、要求仕様の要点
- **チーム構成**（任意）: 既定の 5 人に追加したい専門家、除外したいメンバー、特別な指示

例:
- `ECサイトの注文キャンセル機能の設計。返金フローと在庫戻しも含む。`
- `マルチテナント課金基盤。デフォルトチームに加えて security-expert を追加。`

---

## フェーズ 0: 事前チェックと準備

### 0-1. Agent Teams が有効かを確認

- 現在の値: !`echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-unset}"`

上記が `unset` または `0` なら、次のように伝えて中断する:

> Agent Teams が無効です。以下のいずれかで有効化してください:
> - `~/.claude/settings.json` に `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}` を追加
> - もしくは現在のシェルで `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` してから Claude Code を再起動

有効なら次へ進む。

### 0-2. 作業ディレクトリの準備

対象に短いスラグ（kebab-case、英数字）を付与し、`./spec-planner-output/<slug>/` を作成する。
既存なら `-v2`, `-v3` で避ける。

テンプレートをコピーして初期化する:

```
cp ~/.claude/skills/spec-planner-plan/templates/design.md              ./spec-planner-output/<slug>/design.md
cp ~/.claude/skills/spec-planner-plan/templates/data-model.md          ./spec-planner-output/<slug>/data-model.md
cp ~/.claude/skills/spec-planner-plan/templates/requirements-mapping.md ./spec-planner-output/<slug>/requirements-mapping.md
cp ~/.claude/skills/spec-planner-plan/templates/usecases.md            ./spec-planner-output/<slug>/usecases.md
cp ~/.claude/skills/spec-planner-plan/templates/open-issues.md         ./spec-planner-output/<slug>/open-issues.md
cp ~/.claude/skills/spec-planner-plan/templates/minutes.md             ./spec-planner-output/<slug>/minutes.md
cp ~/.claude/skills/spec-planner-plan/templates/revision-history.md    ./spec-planner-output/<slug>/revision-history.md
```

`data-model.md` は**テーブル定義と ER 図の一次情報**、`design.md` には設計判断のみを書く。`revision-history.md` は初期状態では空テンプレートのまま（`spec-planner-revise` が使用する）。

`design.md` の `{TITLE}` を差し替え、作業ディレクトリをユーザーに通知する。

### 0-3. チーム編成

既定チームは次の 5 人（subagent 定義は `~/.claude/agents/` にある）:

| メンバー | subagent 型 | 役割 |
|---------|------------|-----|
| architect | `spec-planner-architect` | 全体設計・モジュール境界 |
| modeler | `spec-planner-modeler` | データモデル・ER図・ユースケース |
| analyst | `spec-planner-requirements-analyst` | 要求分解・対応表 |
| critic | `spec-planner-critic` | 批判的レビュー (devil's advocate) |
| scribe | `spec-planner-scribe` | 議事録・文書整合性 |

**ドメイン別オプション専門家**（対象ドメインに応じて追加）:

| メンバー | subagent 型 | 役割 | 追加条件 |
|---------|------------|-----|---------|
| ehr | `japan-ehr-specialist` | 日本の電子カルテ法令・標準規格・医療DX政策 | `$ARGUMENTS` に「電子カルテ」「EHR」「診療録」「SS-MIX」「FHIR」「医療情報」「電子処方箋」「PHR」等のキーワードを検出、または明示指定 |
| receipt | `japan-receipt-computer-specialist` | 日本の診療報酬・レセコン・算定要件・審査実務 | `$ARGUMENTS` に「レセコン」「診療報酬」「点数算定」「レセプト」「医事」「算定要件」「施設基準」等のキーワードを検出、または明示指定 |

医療ドメインが対象の場合、両専門家は**委譲ルール**（法令・標準規格は ehr、点数・算定は receipt）で役割が分かれる設計になっているため、両方同時にチーム入りさせることが多い。

$ARGUMENTS にチーム構成の指定（追加・除外）があれば反映する。指定が無く、ドメインキーワードも検出されない場合はデフォルト 5 人で進める。

---

## フェーズ 1: エージェントチーム起動

### 1-1. Team コンテキストを先に作る（必須）

`Agent` を `team_name` 付きで呼ぶ前に、**必ず先に** `TeamCreate` で team コンテキストを作成する。
これを飛ばすと `Not in a team context. Create a team with Teammate spawnTeam first, or set CLAUDE_CODE_TEAM_NAME.` で失敗する。

```
TeamCreate({
  team_name: "spec-planner-plan-<slug>",
  description: "spec-planner-plan: <設計対象>"
})
```

team_name は kebab-case（先頭は英字、英数字とハイフンのみ）。`<slug>` はフェーズ 0-2 と同じ値を使う。

### 1-2. チームメンバーを並列生成

`TeamCreate` 成功後、**同一メッセージ内で**（並列に）0-3 で確定したメンバー数ぶんの `Agent` tool を呼ぶ。各呼び出しには以下を必ず指定する:

- `subagent_type`: 既定 5 人は `spec-planner-architect` / `spec-planner-modeler` / `spec-planner-requirements-analyst` / `spec-planner-critic` / `spec-planner-scribe`。ドメイン専門家は `japan-ehr-specialist` / `japan-receipt-computer-specialist`
- `name`: `architect` / `modeler` / `analyst` / `critic` / `scribe` / `ehr` / `receipt`（SendMessage の宛先になる）
- `team_name`: 1-1 で作成した team_name（**省略厳禁**）
- `description`: 短い役割説明
- `prompt`: 下記の初期プロンプト

ドメイン専門家を追加した場合は、他メンバーへの初期プロンプトにも**専門家の存在と委譲ルール**を明記する（医療系の法令・規格質問は `ehr` に、点数・算定は `receipt` に振る）。

### 1-3. 初期プロンプトに必ず含める項目

1. **対象の要求仕様**（$ARGUMENTS の本文全文）
2. **作業ディレクトリの絶対パス**: `./spec-planner-output/<slug>/`
3. **team_name**（他メンバーへの SendMessage で使用）と**自分の name**、**他メンバーの name 一覧**
4. **各ファイルの役割と役割別必読リスト**:
   - `design.md`: アーキテクチャ・モジュール構成・主要設計判断・非機能要件への対応
   - `data-model.md`: **テーブル定義と ER 図の一次情報**。冒頭に ER 図、以下にテーブル単位で役割・スキーマを簡潔に記述
   - `requirements-mapping.md`: 要求 ↔ 設計の対応表
   - `usecases.md`: ユースケースごとの入出力・状態遷移・データフロー
   - `open-issues.md`: 未決事項・持ち越し論点
   - `minutes.md`: 初回設計時のラウンド議事録（`spec-planner-revise` では触らない）
   - `revision-history.md`: 改訂履歴（`spec-planner-revise` が使用）

   **各メンバーは**初回に自分の担当ファイルのみ通読すればよい（全員全読みはしない）:
   - architect: `requirements-mapping.md` / `design.md` / `open-issues.md`
   - modeler: `requirements-mapping.md` / `data-model.md` / `usecases.md` / `design.md` の該当節
   - analyst: `requirements-mapping.md` / 要求仕様本文 / `open-issues.md`
   - critic: 該当ラウンドでリーダーから broadcast される差分サマリ + `open-issues.md`
   - scribe: 全ファイル（整合チェックのため最終ラウンドは全読み、各ラウンド中は差分のみ）
   - ehr / receipt: 自分に振られた質問文と、その質問が指す成果物の該当節のみ

   **2 ラウンド目以降**はリーダーが broadcast する「差分サマリ」だけ読む。他ファイルは自分の作業に必要なときだけ Read する。
5. **設計原則**（必ず転記）:
   - 要求を満たす最小の設計を第一候補とする
   - ただしシンプルすぎて負債が溜まる設計は却下する
   - 判断は常に「なぜ」とセットで残す
   - 他メンバーに対して合理的かつ厳しく批判する
   - 合意なき妥協をしない。反駁されたら認める
6. **文書品質原則**（必ず転記、成果物を書くときに厳守）:
   - **読み手はこのシステムを既に知る熟練エンジニア**。背景説明・用語定義・一般論は書かない
   - **箇条書きは本当に列挙可能な離散項目のみ**。設計判断の理由・経緯・トレードオフは**散文**で書く（箇条書きは読みづらい）
   - **採用した決定と、却下した代替案を却下理由とともに書く**。両論併記やトレードオフの羅列は禁止
   - **抽象語単独禁止**。「スケーラブル」「堅牢」「高性能」等は、具体的な数値・メカニズム・具体例を添えなければ書かない
   - 初稿完成後に scribe が「30% 削減・情報密度向上」パスを行う（フェーズ 3 で実施）
7. **ラウンド制**: ラウンド数は**固定しない**。critic（および参加していればドメイン専門家）の重大指摘が尽きるまで継続。各ラウンドの目的はリーダー（=あなた）が宣言する
8. **対話の自由**: メンバー同士は SendMessage で直接対話してよい（宛先は name）

## フェーズ 2: ラウンド進行

**ラウンド数は固定しない**。critic（およびドメイン専門家が参加している場合はその専門家）の**重大指摘が尽きるまで**継続する。最低 1 ラウンドは必ず実施する。

**各ラウンドの最低構成**:

1. リーダーがラウンド番号と目的、**前ラウンドからの差分サマリ**をチームに broadcast（2 ラウンド目以降）
2. 担当メンバーがドラフトを書く。**独立な作業（例: architect のモジュール分割と modeler のデータモデル）は、リーダーが同一メッセージで並列 SendMessage し、逐次にしない**
3. critic が批判的論点を提起（ゼロ提起は許されない。無ければリーダーが観点を指示して再検討させる）
4. 全論点が解消（または open-issues 行き）するまで対話
5. scribe が `minutes.md` にそのラウンドの記録を追記（論点→結論の形式、議論過程の逐語は避ける）
6. リーダーが次ラウンドの要否を判断:
   - **継続**: critic（またはドメイン専門家）が新たな重大論点を提起した / 未解消の論点が残っている / 要求に追加が発生した
   - **終了**: critic が「重大な指摘なし」と明示的に合意し、全メンバーがドラフトに異議なし、`open-issues.md` に残る項目は全て低重要度または合意済み

**ラウンド目的のガイド**（リーダーが各ラウンド冒頭で宣言する。以下は典型例で、順序や要否は対象に応じて調整する）:

- 要求分解とスコープ確定、ラフな全体構造（analyst + architect）
- データモデル初版と主要ユースケースの列挙（modeler）
- 批判的レビューとモジュール境界の再検討（critic + architect）
- 要求対応表のギャップ埋めと未対応要求の解決（analyst）
- 非機能・運用・障害シナリオの検証（critic + modeler）
- open-issues の集中解消、必要なら再モデリング（全員）

**暴走防止**: 同一論点で 2 ラウンド連続して合意に至らない場合、その論点は `open-issues.md` に「未決」で移し、次ラウンドでは別論点に進む。リーダーが 10 ラウンドを超えそうと判断した時点でユーザーに中間報告し、継続可否を確認する。

### ラウンド間で必ず確認

- [ ] `requirements-mapping.md` の未対応要求数が減っているか
- [ ] `open-issues.md` に今回の議論で新しく浮上した点が追加されたか
- [ ] `design.md` / `data-model.md` / `usecases.md` の更新理由が `minutes.md` に紐づくか
- [ ] `data-model.md` の ER 図とテーブル一覧が `design.md` の設計判断と矛盾していないか
- [ ] 成果物間で用語・ID・テーブル名・カラム名が一致しているか（scribe にチェックさせる）

## フェーズ 3: 最終統合

最終ラウンド後、scribe に以下を**順に**依頼:

1. **整合チェック**: 全成果物を通読し、用語・参照・矛盾を最終チェック
2. **30% 削減パス**: `design.md` / `usecases.md` / `requirements-mapping.md` を対象に、**情報密度を上げて最低 30% 行数を削減する**（`data-model.md` はもともと簡潔志向なので、重複があれば整理する程度）。具体的には:
   - 同じ内容を別の言い方で書いている箇所を統合する
   - 自明な説明・冗長な前置き・目次の水増しを削除する
   - 箇条書きを散文に書き換える（本当に列挙可能な離散項目は残す）
   - 抽象語単独の記述は、具体化するか削除する
   - 両論併記は採用決定＋却下理由の形に書き換える
3. **冒頭整備**: `design.md` 冒頭の「目的とスコープ」は、**既にシステムを知る熟練エンジニア**を読み手と想定して最短で意図が伝わる形に整える。背景説明は書かない
4. **議事録まとめ**: `minutes.md` 末尾に「最終まとめ」を追記
5. **未決整理**: `open-issues.md` を重要度順にソートし、放置した場合の影響を全項目に記載

仕上がりの文書品質基準（scribe に厳守させる）:

- **読み手はこのシステムを既に知る熟練エンジニア**。背景説明・用語定義・一般論は書かない
- 箇条書きは列挙可能な離散項目のみ。設計判断の理由・経緯は散文
- 決定とその却下理由のみ記述。両論併記・トレードオフの羅列は禁止
- 「スケーラブル」「堅牢」等の抽象語は必ず数値・メカニズム・具体例を伴う
- 「目的 → 前提 → 結論 → 根拠 → 詳細 → 未決事項」の論理順
- 記述は最小、情報量は最大（冗長な前置き・自明な説明・目次の水増しなし）

## フェーズ 4: クリーンアップと報告

1. 各メンバーに `SendMessage({to: "<name>", message: {type: "shutdown_request"}})` でシャットダウンを依頼
2. 全員のアイドル/停止を確認したら `TeamDelete` を呼んで team リソースを削除
   - `TeamDelete` はアクティブメンバーが残っているとエラーになる。その場合は再度シャットダウンを送る
3. ユーザーに以下を報告:
   - 作業ディレクトリの絶対パス
   - 実行ラウンド数
   - 成果物 5 本のそれぞれ何ラインか
   - `open-issues.md` の未決事項件数
   - 特に注目すべき判断・論点を 3 件以内

---

## 運営上の厳守事項

- **合意なき妥協をしない**: 議論ポイントは解消まで続ける。解消できないものは `open-issues.md` に明示（放置しない）。
- **沈黙を許さない**: critic が 1 ラウンドで新しい指摘ゼロなら、リーダーが観点を指示して再検討させる。
- **成果物は毎ラウンド更新**: 議論だけで終わらせない。ファイルに反映させて初めてそのラウンドを閉じる。
- **並列性を活かす**: 独立な作業指示は**同一メッセージで複数 SendMessage** を並べる。逐次化はトークンと壁時間の無駄。レビュー依頼も、受け手が独立に判断できるなら並列化する。
- **ファイル読みは最小限**: 各メンバーは主担当ファイル以外を毎ラウンド読まない。リーダーの差分サマリで足りるよう運営する。
- **ユーザーには中間報告を最小限に**: 各ラウンド完了時に 1〜2 行のサマリだけ出す。詳細はすべてファイルに。
- **$ARGUMENTS に要求仕様の本文が薄い場合**: 即座に止めて、具体の要求を問う。推測で進めない。

## 参照

- [Agent Teams docs](https://code.claude.com/docs/ja/agent-teams)
- subagent 定義: `~/.claude/agents/spec-planner-*.md`
- 出力テンプレート: `~/.claude/skills/spec-planner-plan/templates/`
