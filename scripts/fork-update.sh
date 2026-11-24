#!/usr/bin/env bash
# Updates the personal fork to an official stable release: merge the tag, test, install, push.
#
#   scripts/fork-update.sh 0.1.18
#
# Exit codes: 0 done, 1 failure (see the log it names), 2 merge conflicts to resolve.
# After resolving conflicts, `git add` the files and run the same command again; it commits the merge and continues.
set -euo pipefail

version="${1:-}"
version="${version#v}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/fork-update.sh <stable version, e.g. 0.1.18>" >&2
  exit 1
fi
tag="v$version"

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
logs="$repo/.cache/fork-update-$tag"
mkdir -p "$logs"

step() { printf '\n==> %s\n' "$*"; }
fail() {
  echo "FAILED: $*" >&2
  exit 1
}
# Runs a command with its output in a log, printing only the tail when it fails.
logged() {
  local name="$1"
  shift
  if ! "$@" >"$logs/$name.log" 2>&1; then
    tail -40 "$logs/$name.log" >&2
    fail "$name (full log: $logs/$name.log)"
  fi
}
# Background QoS and few jobs, like install-fork-macos (HERDR_BUILD_JOBS=0 lifts the cap).
jobs="${HERDR_BUILD_JOBS:-4}"
[[ $jobs == 0 ]] && jobs=$(sysctl -n hw.ncpu)
cargo() { taskpolicy -b mise x zig@0.16.0 rust@stable -- "$HOME/.cargo/bin/cargo" "$@"; }

# --- Repository state.
step "Preflight"
upstream_url="$(git remote get-url upstream 2>/dev/null || true)"
[[ "$upstream_url" == *herdrdev/herdr-app* ]] || fail "remote 'upstream' is '$upstream_url', expected herdrdev/herdr-app"
if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
  fail "a rebase is in progress"
fi
git fetch --quiet upstream "refs/tags/$tag:refs/tags/$tag" || fail "could not fetch $tag from upstream"
target="$(git rev-parse "$tag^{commit}")"

merge_head="$(git rev-parse -q --verify MERGE_HEAD || true)"
if [ -n "$merge_head" ]; then
  [ "$merge_head" = "$target" ] || fail "an unrelated merge is in progress (MERGE_HEAD $merge_head)"
  unmerged="$(git diff --name-only --diff-filter=U)"
  [ -z "$unmerged" ] || {
    echo "$unmerged"
    echo "Resolve and 'git add' these, then re-run." >&2
    exit 2
  }
  step "Committing resolved merge of $tag"
  git commit --no-verify --no-edit -q
elif ! git merge-base --is-ancestor "$target" HEAD; then
  [ -z "$(git status --porcelain --untracked-files=no)" ] || fail "working tree has uncommitted changes; commit them first"
  step "Merging $tag"
  if ! git -c rerere.enabled=true merge --no-ff --no-verify -m "chore: merge stable $tag into personal fork" "$tag" >"$logs/merge.log" 2>&1; then
    unmerged="$(git diff --name-only --diff-filter=U)"
    if [ -n "$unmerged" ]; then
      echo "Conflicts (rerere may have pre-resolved others):"
      echo "$unmerged"
      echo "Resolve and 'git add' these, then re-run: scripts/fork-update.sh $version" >&2
      exit 2
    fi
    # rerere resolved everything it recorded before.
    git commit --no-verify --no-edit -q
  fi
else
  echo "$tag already merged"
fi

built="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"
[ "$built" = "$version" ] || fail "Cargo.toml says $built after merging $tag, expected $version"

# --- Verify.
step "Tests"
logged test cargo test --locked -j "$jobs" -- --test-threads "$jobs"

# --- Install into /Applications/Herdr.app and confirm it's the fork at this version.
step "Install"
logged install scripts/install-fork-macos
installed="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Herdr.app/Contents/Info.plist)"
[[ "$installed" == "$version.fork" ]] || fail "installed app reports '$installed', expected $version.fork"
grep -q "Prepare update" /Applications/Herdr.app/Contents/MacOS/Herdr || fail "installed app is missing the fork's update check"
installed="$installed (Build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Herdr.app/Contents/Info.plist))"
echo "$installed"

step "Push"
logged push git push -u origin HEAD

step "Done: $tag merged, tested, installed ($installed) and pushed. Restart Herdr to use it."
