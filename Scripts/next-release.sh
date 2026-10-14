#!/bin/bash
# Decides the next version from the Conventional Commits since the last `v*` tag, and writes
# the release notes for it.
#
#   Scripts/next-release.sh            prints the next version, or nothing when there is
#                                      nothing to release (docs, tests, CI only)
#   Scripts/next-release.sh --notes    prints the release notes, Markdown
#
# VERSION in the environment overrides the derived version — for a release forced by hand
# (the workflow's `version` input) or a baseline tag.
#
# Bump rules, from the commit subjects (`type(scope)!: description`) and bodies:
#   `!` or "BREAKING CHANGE"  → major        1.1   → 2.0
#   feat                      → minor        1.1   → 1.2
#   fix, perf                 → patch        1.1   → 1.1.1
#   anything else             → no release
# Versions are written the way the store shows them: two components, a third only for a
# patch. Read by .github/workflows/release.yml.
set -euo pipefail

cd "$(dirname "$0")/.."

last_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
if [[ -n "$last_tag" ]]; then
  range="$last_tag..HEAD"
  base_version="${last_tag#v}"
else
  range="HEAD"
  base_version="0.0"
fi

IFS=. read -r major minor patch <<< "$base_version"
patch="${patch:-0}"

# One record per commit: sha, type, breaking, scope, description. Non-conventional
# subjects are kept under "other" so nothing silently vanishes from the notes.
conventional='^([a-z]+)(\(([^)]*)\))?(!)?: (.*)$'
sep=$'\x1f' # not whitespace, so empty fields survive `read`
commits=()
while IFS= read -r sha; do
  subject="$(git log -1 --format=%s "$sha")"
  body="$(git log -1 --format=%b "$sha")"
  type=other scope="" bang="" description="$subject"
  if [[ "$subject" =~ $conventional ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    description="${BASH_REMATCH[5]}"
  fi
  breaking=0
  if [[ -n "$bang" || "$body" == *"BREAKING CHANGE"* ]]; then
    breaking=1
  fi
  commits+=("$sha$sep$type$sep$breaking$sep$scope$sep$description")
done < <(git rev-list --no-merges "$range")

bump=none
for line in ${commits[@]+"${commits[@]}"}; do
  IFS="$sep" read -r _ type breaking _ _ <<< "$line"
  if (( breaking )); then
    bump=major
  elif [[ "$type" == feat && "$bump" != major ]]; then
    bump=minor
  elif [[ "$type" == fix || "$type" == perf ]] && [[ "$bump" == none ]]; then
    bump=patch
  fi
done

case "$bump" in
  major) version="$((major + 1)).0" ;;
  minor) version="$major.$((minor + 1))" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  none) version="" ;;
esac
version="${VERSION:-$version}"
[[ -n "$version" ]] || exit 0

if [[ "${1:-}" != "--notes" ]]; then
  echo "$version"
  exit 0
fi

section() {
  local title="$1" want_type="$2" want_breaking="$3" printed=0
  for line in ${commits[@]+"${commits[@]}"}; do
    IFS="$sep" read -r sha type breaking scope description <<< "$line"
    if (( want_breaking )); then
      (( breaking )) || continue
    else
      (( breaking )) && continue
      [[ " $want_type " == *" $type "* ]] || continue
    fi
    if (( ! printed )); then
      printf '## %s\n\n' "$title"
      printed=1
    fi
    if [[ -n "$scope" ]]; then
      printf -- '- **%s:** %s (%s)\n' "$scope" "$description" "${sha:0:7}"
    else
      printf -- '- %s (%s)\n' "$description" "${sha:0:7}"
    fi
  done
  (( printed )) && echo
  return 0
}

section "Breaking changes" "" 1
section "Features" "feat" 0
section "Fixes" "fix perf" 0
section "Changes" "refactor build other" 0

echo "Mac App Store build $(git rev-list --count HEAD) of version $version."
if [[ -n "$last_tag" ]]; then
  remote="$(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')"
  echo
  echo "**Full changelog:** $remote/compare/$last_tag...v$version"
fi
