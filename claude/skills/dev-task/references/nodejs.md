# Node.js

`dev-task` で Node.js コードを書く前に読むこと。

## バージョンとツール

- プロジェクトの Node バージョンに合わせる (`.nvmrc`、`package.json` の `engines`、CI 設定を確認)。「最新 LTS」と決め打ちしない。
- パッケージマネージャはプロジェクトのものを使う (npm / pnpm / yarn)。lock ファイルから推定。
- 1 行の処理のために新規依存を入れない。既存依存と `node:` ビルトインを先に確認。

## モジュール

- ESM か CommonJS か: プロジェクトに合わせる。`package.json` の `"type"` と既存ファイルを確認。混在は相互運用の地雷。
- ESM ではビルトインを `node:` 接頭辞付きで import (`node:fs`、`node:path`)。CJS で慣習がなければ無印でも可。
- Top-level await は ESM のみ。CJS 文脈に持ち込まない。

## 非同期パターン

- `.then()` チェーンやコールバックより `async`/`await`。
- レガシーなコールバック API は手書きでラップせず `node:util.promisify` を使う。
- 並列化は fail-fast なら `Promise.all`、部分失敗を許すなら `Promise.allSettled`。
- トップレベルのハンドラなしに fire-and-forget しない。Unhandled rejection はプロセス全体に影響する。

## エラー

- 意味ある `name` と `message` を持つ `Error` サブクラスを throw。文字列や生オブジェクトを throw しない。
- 原因を保持: `throw new MyError('context', { cause: err })`。
- `process.on('unhandledRejection')` と `process.on('uncaughtException')` は最終手段のログ。制御フローに使わない。

## I/O

- 大きなデータはストリーム。合成は `node:stream/promises` の `pipeline`。
- ファイルパスは `node:path` (`path.join`、`path.resolve`)。文字列を `/` で連結しない。
- 設定は起動時に検証する env 変数経由。コード全体に `process.env.X` を散らさない。

## 副作用

- モジュールロード時のトップレベル副作用は禁止。DB 接続、サーバ起動、グローバル変更は、すべてエントリポイントから呼ぶ関数の中に置く。
- リソース後片付けは `try`/`finally` か明示的なクローズ経路で。長寿命リソース(DB プール、ファイルハンドル)は per-request ではなく app 所有のシングルトン。

## テスト

- プロジェクトのフレームワーク (Vitest / Jest / Node 組込み `node:test`) に合わせる。
- モックは境界に。テスト対象モジュールの中をモックしない。
- 実ネットワーク接続や一時ディレクトリ外への書き込みを伴うテストは書かない。

## アンチパターン

- 循環依存回避のため関数内で `require` する → 循環自体を直す。
- `JSON.parse(JSON.stringify(x))` で deep clone → `structuredClone` を使う (Node 17+)。
- 非推奨の `new Buffer()` コンストラクタ → `Buffer.from` / `Buffer.alloc`。
- 起動コード以外で同期 I/O (`fs.readFileSync`、`child_process.execSync`) を使いイベントループをブロック。
