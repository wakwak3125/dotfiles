# Notion 同期状態

> `spec-planner` フェーズ 2 の同期結果を記録する。Notion 側の page_id とローカル md のサイズ・最終同期時刻を保持し、再実行時の再開判定と冪等性確認に使う。
> 実体の page_id マップは `notion-config.json` の `child_pages` に持つ。本ファイルはタイムスタンプと失敗履歴の運用ログ。

## Last Sync

> 子ページごとの最終同期。同じキーは置換する（履歴は残さない。履歴は revision-history.md / minutes.md 側で表現）。

| key | page_id | synced_at | md_size_bytes |
|-----|---------|-----------|---------------|
| requirements | - | - | - |
| usecases | - | - | - |
| design | - | - | - |
| data-model | - | - | - |
| requirements-mapping | - | - | - |
| open-issues | - | - | - |
| revision-history | - | - | - |
| minutes | - | - | - |

## Failures

> 同期失敗時のみ追記。成功時の再実行で当該行を削除する。

| key | failed_at | error_summary |
|-----|-----------|---------------|

## Notes

<!-- 同期運用上のメモ。Notion 側でユーザーが手動編集した子ページがある場合、次回 sync で上書きされる点に注意するなど。 -->
