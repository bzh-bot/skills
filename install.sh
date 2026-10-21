#!/usr/bin/env bash
# install.sh — link the skills in this repo into ~/.agents/skills/
#
#   ./install.sh                 link every skill
#   ./install.sh slack zellij   link only the named ones
#   ./install.sh --copy         copy instead of symlink (containers, throwaway VMs)
#   DEST=/some/path ./install.sh  install somewhere other than ~/.agents/skills
#   PI=0 ./install.sh            skip the .pi/agent themes/extensions copy
#
# Skills resolve from <dest>/<name>/SKILL.md, where <name> is the directory name and
# should match the `name:` in its frontmatter.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo mirrors $HOME, so a plain clone holds .agents/skills/<name>/SKILL.md;
# a bare checkout used as a work-tree at $HOME has the skills at the same relative
# path. Support both by picking the directory that actually contains SKILL.md files.
if [ -d "$ROOT/.agents/skills" ]; then SRC="$ROOT/.agents/skills"; else SRC="$ROOT"; fi
DEST="${DEST:-$HOME/.agents/skills}"
MODE="link"
names=()

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) names+=("$arg") ;;
  esac
done

mkdir -p "$DEST"

# every directory that carries a SKILL.md is a skill
all=()
while IFS= read -r f; do
  d="$(dirname "$f")"
  all+=("$(basename "$d")")
done < <(find "$SRC" -mindepth 2 -maxdepth 2 -name SKILL.md | sort)

if [ ${#names[@]} -gt 0 ]; then
  for n in "${names[@]}"; do
    if [ ! -f "$SRC/$n/SKILL.md" ]; then
      echo "no such skill: $n" >&2
      exit 1
    fi
  done
  targets=("${names[@]}")
else
  targets=("${all[@]}")
fi

for n in "${targets[@]}"; do
  src="$SRC/$n"; dst="$DEST/$n"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
      echo "  ok    $n (already linked)"
      continue
    fi
    echo "  skip  $n (exists and is not our link): $dst" >&2
    continue
  fi
  case "$MODE" in
    link) ln -s "$src" "$dst"; echo "  link  $n -> $src" ;;
    copy) cp -R "$src" "$dst"; echo "  copy  $n" ;;
  esac
done

# pi resources: a theme and a few extensions, if this repo carries them
if [ "${PI:-1}" = 1 ] && [ -d "$ROOT/.pi/agent" ]; then
  target="$HOME/.pi/agent"
  mkdir -p "$target"
  for kind in themes extensions extensions-config; do
    [ -d "$ROOT/.pi/agent/$kind" ] || continue
    mkdir -p "$target/$kind"
    cp -R "$ROOT/.pi/agent/$kind/." "$target/$kind/" 2>/dev/null || true
    echo "  pi    $kind -> $target/$kind"
  done
fi

echo
echo "$(printf '%s\n' "${targets[@]}" | wc -l) skill(s) in $DEST"
echo "restart pi (or start a new session) to pick them up"
