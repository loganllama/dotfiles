#!/usr/bin/env bash
# Generate a markdown PR stack description for pasting into PR descriptions.
#
# Usage:
#   ./scripts/pr-stack-description.sh [bookmark]
#   ./scripts/pr-stack-description.sh @          # use current working-copy revision
#
# If bookmark is omitted, presents an interactive picker of all bookmarks.
# Output is an HTML <pre> block with clickable PR links and graph alignment.
set -euo pipefail
bookmark="${1:-}"
if [[ "$bookmark" == "@" ]]; then
  # Resolve from working copy
  bookmark=$(jj log -r @ --no-graph -T 'bookmarks.join(",")' 2>/dev/null)
  if [[ -z "$bookmark" ]]; then
    echo "Error: no bookmark on current working-copy commit." >&2
    exit 1
  fi
elif [[ -z "$bookmark" ]]; then
  # Interactive picker: list all bookmarks with their descriptions
  mapfile -t entries < <(
    jj log --no-graph \
      -r 'bookmarks() & ~ancestors(trunk())' \
      -T 'bookmarks.join(",") ++ "\t" ++ description.first_line() ++ "\n"'
  )
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "No bookmarks found." >&2
    exit 1
  fi
  echo "Select a bookmark:" >&2
  for i in "${!entries[@]}"; do
    bm="${entries[$i]%%$'\t'*}"
    desc="${entries[$i]#*$'\t'}"
    printf "  %d) %s  %s\n" "$((i + 1))" "$bm" "$desc" >&2
  done
  printf "Enter number: " >&2
  read -r choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#entries[@]} )); then
    echo "Invalid selection." >&2
    exit 1
  fi
  bookmark="${entries[$((choice - 1))]%%$'\t'*}"
fi
# Scope to only the connected stack: ancestors and descendants of the target
# bookmark, excluding trunk history.
stack_revset="(ancestors($bookmark) | descendants($bookmark)) & ancestors(bookmarks()) & ~ancestors(trunk())"
# Build maps of bookmark -> PR number and URL from gh
declare -A pr_nums
declare -A pr_urls
while IFS=$'\t' read -r branch number url; do
  pr_nums["$branch"]="$number"
  pr_urls["$branch"]="$url"
done < <(gh pr list --author "@me" --json headRefName,number,url --jq '.[] | [.headRefName, (.number | tostring), .url] | @tsv' 2>/dev/null || true)
# Get the jj graph with parseable bookmark markers
output=$(jj log -r "$stack_revset" -T '
  if(bookmarks,
    "«" ++ bookmarks.join(",") ++ "» " ++ description.first_line(),
    description.first_line()
  )
')
# Annotate: replace «bookmark» markers with clickable PR links
result=""
while IFS= read -r line; do
  if [[ "$line" =~ «([^»]+)» ]]; then
    bm="${BASH_REMATCH[1]}"
    num="${pr_nums[$bm]:-}"
    url="${pr_urls[$bm]:-}"
    if [[ -n "$num" ]]; then
      annotation="<a href=\"$url\">#$num</a>"
    else
      annotation="$bm (no PR)"
    fi
    if [[ "$bm" == "$bookmark" ]]; then
      annotation="$annotation  👈 this PR"
    fi
    line="${line/«${bm}»/$annotation}"
  fi
  result+="$line"$'\n'
done <<< "$output"
echo '<pre>'
printf '%s' "$result"
echo '</pre>'
