#!/bin/sh
# Builds hermod-bench-app against each given revision of this repository and
# prints one `--bin=REF=PATH` line per revision, for hermod-bench-compare.
#
# Each revision is checked out in a git worktree (under
# dist-newstyle/bench-app-worktrees, or $WORKDIR); where it doesn't contain the
# app, the worktree gets a cabal.project.local that adds this checkout's app.
# Build output goes to stderr.
#
#     examples/hermod-bench-app/build.sh master mkarg/opt-trace-filtering
set -eu

app_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(git -C "$app_dir" rev-parse --show-toplevel)
workdir=${WORKDIR:-$repo/dist-newstyle/bench-app-worktrees}
expected=$(sed -n 's/.*-with-rtsopts=\([^"]*\)".*/\1/p' "$app_dir/hermod-bench-app.cabal")

for ref in "$@"; do
  rev=$(git -C "$repo" rev-parse --verify "$ref^{commit}")
  tree=$workdir/$(printf %s "$ref" | tr -c 'A-Za-z0-9._-' _)
  if [ -d "$tree" ]; then
    git -C "$tree" checkout --quiet --detach --force "$rev"
  else
    mkdir -p "$workdir"
    git -C "$repo" worktree add --quiet --detach "$tree" "$rev"
  fi
  if [ ! -d "$tree/examples/hermod-bench-app" ]; then
    printf 'packages: %s\n' "$app_dir" > "$tree/cabal.project.local"
  fi
  echo "building $ref ($(printf %.9s "$rev")) in $tree" >&2
  (cd "$tree" && cabal build -v1 exe:hermod-bench-app >&2)
  bin=$(cd "$tree" && cabal list-bin exe:hermod-bench-app)

  # A changed -with-rtsopts doesn't relink: GHC skips linking when no object
  # changed, and cabal then reports the package up to date.
  actual=$("$bin" +RTS --info -RTS | sed -n 's/.*"Flag -with-rtsopts", "\([^"]*\)".*/\1/p')
  if [ "$actual" != "$expected" ]; then
    echo "$bin was built with -with-rtsopts='$actual', the cabal file says '$expected':" >&2
    echo "a stale link; delete $(dirname "$(dirname "$(dirname "$bin")")")/cache and run again" >&2
    exit 1
  fi
  echo "--bin=$ref=$bin"
done
