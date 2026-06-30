#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${1:-$ROOT/agents/skills/manifest.tsv}"
CACHE_ROOT="${AGENT_SKILLS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-agent-skills}"

warn() {
  echo "==> WARN: $*" >&2
}

require_gh_skill() {
  if ! command -v gh &>/dev/null; then
    warn "gh not found, skipping agent skill install"
    return 1
  fi

  if ! gh skill --help &>/dev/null; then
    local version
    version="$(gh --version 2>/dev/null | head -n 1 || true)"
    warn "gh skill is unavailable (${version:-unknown gh version}); upgrade GitHub CLI and re-run bootstrap"
    warn "manual: https://cli.github.com/manual/gh_skill"
    return 1
  fi
}

skill_dir_for_agent() {
  case "$1" in
    claude-code)
      printf '%s\n' "$HOME/.claude/skills"
      ;;
    codex)
      printf '%s\n' "$HOME/.codex/skills"
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_skill_dir() {
  local agent="$1"
  local dir

  dir="$(skill_dir_for_agent "$agent")"

  if [[ -L "$dir" ]]; then
    echo "==> Replacing legacy skill symlink: $dir"
    rm "$dir"
  fi

  mkdir -p "$dir"
}

stage_skill() {
  local stage_root="$1"
  local skill_path="$2"
  local skill_dir skill_name dest

  skill_dir="$ROOT/${skill_path%/SKILL.md}"
  skill_name="$(basename "$skill_dir")"
  dest="$stage_root/skills/$skill_name"

  if [[ ! -f "$skill_dir/SKILL.md" ]]; then
    warn "$skill_dir/SKILL.md not found, skipping"
    return 1
  fi

  if command -v rsync &>/dev/null; then
    mkdir -p "$dest"
    rsync -a --delete --exclude node_modules "$skill_dir/" "$dest/"
  else
    rm -rf "$dest"
    mkdir -p "$dest"
    (cd "$skill_dir" && tar --exclude './node_modules' -cf - .) | (cd "$dest" && tar -xf -)
  fi
}

install_skill() {
  local stage_root="$1"
  local agent="$2"
  local skill_path="$3"
  local skill_name skill_root skill_dest

  skill_name="$(basename "${skill_path%/SKILL.md}")"
  skill_root="$(skill_dir_for_agent "$agent")"
  skill_dest="$skill_root/$skill_name"

  prepare_skill_dir "$agent"
  if [[ -L "$skill_dest" ]]; then
    echo "==> Replacing legacy skill symlink: $skill_dest"
    rm "$skill_dest"
  fi

  echo "==> Installing $skill_path for $agent"
  gh skill install "$stage_root" "$skill_name" --from-local --agent "$agent" --scope user --force
}

main() {
  require_gh_skill || return 0

  local stage_root skill_path agents agent
  local -a agent_list

  stage_root="$CACHE_ROOT"
  mkdir -p "$stage_root/skills"

  while IFS=$'\t' read -r skill_path agents; do
    [[ -n "$skill_path" ]] || continue
    [[ "$skill_path" == \#* ]] && continue

    stage_skill "$stage_root" "$skill_path"

    IFS=',' read -ra agent_list <<< "$agents"
    for agent in "${agent_list[@]}"; do
      install_skill "$stage_root" "$agent" "$skill_path"
    done
  done < "$MANIFEST"
}

main "$@"
