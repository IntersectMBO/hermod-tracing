#!/usr/bin/env bash

## SRPs from local folders might not always work with each nix setup,
## depending on the presence and the permissions of nix build users
## and the internal usage of fetchgit vs. fetchGit.
##
## For ease of use, this script requires the commit to be used as
## SRP is published on some 'git remote' - be it the GitHub
## source, a GitHub fork, or just some box reachable via SSH.

# find out which remote the current branch is tracking
GIT_REMOTE=$(git rev-parse --abbrev-ref HEAD@{upstream} | cut -d/ -f1)

# commit hash of HEAD commit
GIT_SHA=$(git rev-parse HEAD)

ORIGIN_URL=$(git config --get remote.${GIT_REMOTE}.url)

RESULT=$(nix-prefetch-git --url $ORIGIN_URL --rev $GIT_SHA --quiet)

TAG=$(echo $RESULT | jq -r '.rev')
HASH=$(echo $RESULT | jq -r '.hash')

echo "-- SRP for trace-dispatcher (add this to another project's cabal.project)"
echo "source-repository-package"
echo "  type: git"
echo "  location: $ORIGIN_URL"
echo "  tag: $TAG"
echo "  --sha256: $HASH"
echo "  subdir:"
echo "    trace-dispatcher"
