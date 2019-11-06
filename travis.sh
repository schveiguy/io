#!/usr/bin/env bash

set -ueo pipefail

if ! { ifconfig | grep -qF ::1; }; then
    export SKIP_IPv6_LOOPBACK_TESTS=
fi

: ${CONFIG:=library} # env CONFIG=dip1000 ./travis.sh

if [[ -n "${COVERAGE:-}" ]]; then
    dub test -b unittest-cov -c $CONFIG
else
    dub test -c $CONFIG
fi

if [[ ! -z "${GH_TOKEN:-}" ]]; then
    dub build -b ddox

    # push docs to gh-pages branch
    cd docs
    git init
    git config user.name 'Travis-CI'
    git config user.email '<>'
    git add .
    git commit -m 'Deployed to Github Pages'
    git push --force --quiet "https://${GH_TOKEN}@github.com/${TRAVIS_REPO_SLUG}" master:gh-pages
fi
