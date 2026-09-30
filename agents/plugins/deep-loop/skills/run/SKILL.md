---
name: run
description: deep-loop の作業ディレクトリを受け取り、1 ラウンド分の Workflow を最大 3 回回してから最終の成果物を書かせる指揮役。deep-loop の runner が夜間の claude -p から「/deep-loop:run <作業ディレクトリ>」で呼ぶ。人が直接呼ぶものではない（始めるときは deep-loop skill を使う）。
---

# deep-loop の指揮役

引数の作業ディレクトリ（以下 `DIR`）について、1 ラウンド分の Workflow を最大 3 回回し、最後に成果物を書く Workflow を回す。
この skill の指示で Workflow を呼ぶことが、Workflow を使う明示の依頼にあたる。

あなたは指揮役であり、調べもの、設計、ノートや state の中身の読み込みを自分ではしない。
経緯は作業ディレクトリのファイルと Workflow の中に持たせ、あなたの context には各ラウンドの要約だけを残す。
何ラウンド回しても指揮役の context が膨らまないようにするためである。
夜間の無人実行なので、人に質問しない。

## 準備

1. このスキルの base directory の 2 つ上が plugin のディレクトリ（以下 `PLUGIN`）である。
   Workflow の script は `PLUGIN/workflows/round.js` と `PLUGIN/workflows/finalize.js`、成果物の型は `PLUGIN/templates/` にある。
2. `DIR/meta.json`（`maxRounds`、`repos`、任意で `models` と `efforts`）と `DIR/brief.md` を読む。
   `maxRounds` は 3 を超えない。
3. モデルと effort は次を既定にし、`meta.json` に書かれた役だけ上書きする。
   作業役を Sonnet にして費用を抑え、判断が後段すべてに効く役（課題の選び方、反証、統合、最終の成果物）を Opus にしている。

   | 役 | model | effort |
   | -- | -- | -- |
   | planner | opus | xhigh |
   | worker | sonnet | medium |
   | verifier | opus | high |
   | integrator | opus | high |
   | writer | opus | xhigh |

4. `DIR/journal.jsonl` があれば読み、`"round"` を持つ行の数を完了したラウンド数にする。
   `"final": true` の行があれば、成果物まで済んでいるので何もせずに終える。

## ラウンドを回す

完了したラウンド数の次から `maxRounds` まで、1 ラウンドずつ次を行う。
`RNN` はラウンド番号を 2 桁にしたもの（`r01`）。

1. 前回の実行が途中で落ちた残骸を捨てる: `rm -rf DIR/rounds/RNN DIR/state.next.md` のあと `mkdir -p DIR/rounds/RNN`。
2. Workflow を `scriptPath: PLUGIN/workflows/round.js` で呼ぶ。`args` は次の JSON にする。
   ```json
   {
     "round": 1,
     "maxRounds": 3,
     "brief": "<DIR/brief.md の全文>",
     "repos": ["<meta.json の repos>"],
     "previous": ["r01: <journal の summary>"],
     "statePath": "DIR/state.md",
     "nextStatePath": "DIR/state.next.md",
     "roundsDir": "DIR/rounds",
     "stateMaxLines": 300,
     "models": { "planner": "opus", "worker": "sonnet", "verifier": "opus", "integrator": "opus" },
     "efforts": { "planner": "xhigh", "worker": "medium", "verifier": "high", "integrator": "high" }
   }
   ```
   パスはすべて絶対パスで渡す。Workflow の完了を待ってから次に進む。
3. 戻り値の `status` で分ける。
   - `failed`：同じ `scriptPath` と `args` に `resumeFromRunId` を付けて 1 回だけ呼び直す。終わった作業役の結果は使い回される。
     それでも `failed` なら、`{"round": N, "status": "failed", "reason": "..."}` を journal に足してラウンドを打ち切り、成果物へ進む。
   - `done`：`{"round": N, "status": "done", "reason": "..."}` を journal に足し、ラウンドを打ち切って成果物へ進む。
     planner が「続ける課題が無い」と判断した正常な終わり方である。
   - `ok`：次の 4 と 5 を行う。
4. `DIR/state.next.md` を `DIR/state.md` に移す（`mv`）。中身は読まない。
   `wc -l` で行数だけを確かめ、`stateMaxLines` を超えていたら journal の行に `"stateOverLimit": true` を付ける。
5. 戻り値をそのまま `DIR/rounds/RNN/result.json` に書き、次の 1 行を `DIR/journal.jsonl` に足す。
   ```json
   {"round": 1, "status": "ok", "summary": "...", "progress": 5, "open_questions": 3, "resolved_questions": ["Q1"], "verdicts": {"confirmed": 2, "refuted": 1, "uncertain": 0}, "failed": [], "outputTokens": 123456}
   ```
   journal に行が書かれたラウンドだけを完了と見なす。state の差し替えより後に書くので、間で落ちたら新しい state で同じラウンドをやり直す。
6. `progress` が 0 なら、次のラウンドを回しても同じ結果になるので打ち切る。
   `suggest_done` が true でも打ち切らない。次のラウンドの planner が、本当に終えてよいかを state から判断する。

## 成果物

完了したラウンドが 1 つ以上あれば、Workflow を `scriptPath: PLUGIN/workflows/finalize.js` で呼ぶ。`args` は次のとおり。

```json
{
  "brief": "<DIR/brief.md の全文>",
  "statePath": "DIR/state.md",
  "roundsDir": "DIR/rounds",
  "templatesDir": "PLUGIN/templates",
  "reportPath": "DIR/report.md",
  "models": { "writer": "opus" },
  "efforts": { "writer": "xhigh" }
}
```

戻り値が `ok` で `DIR/report.md` が空でなければ、`{"final": true, "summary": "...", "open_questions": N}` を journal に足す。
`failed` なら 1 回だけ `resumeFromRunId` で呼び直す。

最後に、何ラウンド回して成果物がどこにあるかを 1 行で返して終える。

## しないこと

- 作業ディレクトリの外に書き込まない。リポジトリを変更しない。commit も push も外部サービスへの投稿もしない。
- `state.md`、ノート、照合の結果を読まない。読むのは `meta.json`、`brief.md`、`journal.jsonl` と Workflow の戻り値だけである。
- Workflow の外でサブエージェントを起こさない。調べものの続きを自分でしない。
