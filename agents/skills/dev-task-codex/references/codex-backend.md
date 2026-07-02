# Codex Backend

Claude Code から Codex を呼ぶときは `codex exec` を同期実行する。companion の background job / status / result / resume 管理は使わない。

## Command

標準形:

```bash
codex exec \
  -C "$REPO_ROOT" \
  --profile dev-task-implementer \
  --sandbox workspace-write \
  --ask-for-approval never \
  --ephemeral \
  --output-schema "$DEV_TASK_CODEX_SKILL_DIR/schemas/implementer-result.schema.json" \
  -o "$RESULT_JSON" \
  - < "$PROMPT_FILE"
```

軽微修正:

```bash
codex exec \
  -C "$REPO_ROOT" \
  --profile dev-task-implementer-fast \
  --sandbox workspace-write \
  --ask-for-approval never \
  --ephemeral \
  --output-schema "$DEV_TASK_CODEX_SKILL_DIR/schemas/implementer-result.schema.json" \
  -o "$RESULT_JSON" \
  - < "$PROMPT_FILE"
```

高リスク実装:

```bash
codex exec \
  -C "$REPO_ROOT" \
  --profile dev-task-implementer-heavy \
  --sandbox workspace-write \
  --ask-for-approval never \
  --ephemeral \
  --output-schema "$DEV_TASK_CODEX_SKILL_DIR/schemas/implementer-result.schema.json" \
  -o "$RESULT_JSON" \
  - < "$PROMPT_FILE"
```

## Profiles

Profile は dotfiles の `config/codex/*.config.toml` で管理し、`script/bootstrap.sh` が `~/.codex/*.config.toml` へ symlink する。

`config/codex/dev-task-implementer.config.toml`:

```toml
model = "gpt-5.4"
model_reasoning_effort = "high"

[[skills.config]]
path = "/Users/wakwak/.codex/skills/dev-task/SKILL.md"
enabled = false
```

`config/codex/dev-task-implementer-fast.config.toml`:

```toml
model = "gpt-5.4-mini"
model_reasoning_effort = "medium"

[[skills.config]]
path = "/Users/wakwak/.codex/skills/dev-task/SKILL.md"
enabled = false
```

`config/codex/dev-task-implementer-heavy.config.toml`:

```toml
model = "gpt-5.5"
model_reasoning_effort = "high"

[[skills.config]]
path = "/Users/wakwak/.codex/skills/dev-task/SKILL.md"
enabled = false
```

`dev-task-codex` は Codex に install しない前提なので profile では指定しない。Codex 側で既存 `dev-task` が implicit に発火しないよう、`dev-task` だけを無効化する。

## Prompt Contract

Codex への prompt は次の形にする。

```text
You are a bounded implementation backend.

Do not run the full dev-task workflow.
Do not use dev-task or dev-task-codex skills.
Do not commit, push, create PRs, create branches, create worktrees, or modify files outside the allowed write scope.

Read:
- workspec: <path>
- references: <paths>
- similar implementations: <paths>

Allowed write scope:
- <paths/globs>

Task:
- Implement the accepted workspec/plan with the smallest diff.
- Follow the referenced similar implementation.
- Run only these validation commands if relevant:
  - <commands>

Return only the structured final result requested by the output schema.
```

## Result Schema

最小 schema:

```json
{
  "type": "object",
  "properties": {
    "status": { "enum": ["PASS", "BLOCKED"] },
    "changed_files": {
      "type": "array",
      "items": { "type": "string" }
    },
    "validation": {
      "type": "array",
      "items": { "type": "string" }
    },
    "notes": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "required": ["status", "changed_files", "validation", "notes"],
  "additionalProperties": false
}
```

## Post-Run Gate

Codex が戻ったら Claude Code main が必ず確認する。

- `git diff` に allowed write scope 外の変更がない
- ついでリファクタ、依存更新、format churn がない
- workspec の受け入れ条件を満たしている
- 宣言なしに公開境界へ触れていない
- validation は実際に実行されたものだけが報告されている

違反があれば Codex に最大 2 回まで修正を戻す。収束しない場合は Claude Code が引き取る。
