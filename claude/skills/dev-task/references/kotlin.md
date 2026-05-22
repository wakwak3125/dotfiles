# Kotlin (バックエンド)

`dev-task` で Kotlin コードを書く前に読むこと。

## Null 安全性

- `!!` ではなく `?.` と `?: throw` / `?: return` を優先。`!!` は null が真に不変条件違反である箇所のみで、理由をコメントで残す。
- `lateinit` はフレームワーク注入(Spring Bean、テストフィクスチャ)以外では避ける。可能ならコンストラクタ注入。
- null を逃れるために型を広げない。`String?` はそのまま伝播させる。`!!` で `String` にするのは本来の形を隠す行為。

## コルーチン

- 構造化並行性を守る。`GlobalScope` はほぼ常に誤り。`coroutineScope` / `supervisorScope` か、外側のライフサイクルが所有するスコープを使う。
- `runBlocking` は同期境界 (main、テスト) のみ。suspend 関数内では使わない。
- キャンセルは協調的。長時間 CPU ループは `ensureActive()` か `yield()` をチェックすること。
- ディスパッチャを安易に切り替えない。ブロッキング I/O は `Dispatchers.IO`、CPU 重作業は `Dispatchers.Default`。理由なく `withContext` を散らさない。

## 型モデリング

- 有限の状態 (`Result`、リクエスト種別など) は sealed class / sealed interface。`when` の網羅性チェックが効く。
- DTO や値オブジェクトは `data class`。振る舞いは付けない。ロジックはサービスや拡張関数へ。
- ID や小さなラッパーには inline value class (`@JvmInline value class`) を使い、ID 混同を防ぐ (`UserId`、`OrderId`)。
- `Any` / `Any?` を引数や戻り値の型に使うのは、本当に動的な境界の場合のみ。

## エラー処理

- プログラマの誤りや不変条件違反は throw。呼び出し側が扱うべき想定済みの失敗は `Result<T>` または sealed な `…Outcome` で返す。
- `Throwable` や裸の `Exception` を catch しない。具体的な型を catch する。
- 例外を握りつぶさない。catch するなら原因をログに残すか、ラップして再 throw。

## 採用すべきイディオム

- 手動ループや bang(`!!`)より `mapNotNull`、`firstOrNull`、`single`、`requireNotNull`。
- ビルダ風の設定には `apply` / `also`、null 安全な変換には `let`、スコープ計算には `run`。存在するからといって混ぜない。
- プロジェクト共通のヘルパは拡張関数で。ただしレシーバが明確で安定している場合のみ。`Any`、`String`、`List` にプロジェクト固有の振る舞いを生やすのは避ける。

## 避けるアンチパターン

- `Exception` を catch してコンテキストを足さずに再 throw。
- 無関係な定数を詰め込んだ `companion object`。目的別に `object` を分けるかファイル分割。
- フレームワーク以外でのリフレクションによるフィールドアクセス (`javaField`)。
- 既にシリアライズスタック (kotlinx.serialization、Jackson) があるのに手で JSON パース。
- ヘルパ 1 つのために新規依存導入。先に既存依存と `stdlib` を確認。

## テスト

- プロジェクトのテストフレームワーク (JUnit 5 + Kotest matcher など) に合わせる。新規導入しない。
- テスト 1 つにつき 1 つの振る舞い。テスト名はメソッド名ではなく振る舞いを表す。
- コルーチンのテストは `runBlocking` ではなく `runTest` と `TestDispatcher`。
