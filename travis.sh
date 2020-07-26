#!/usr/bin/env bash

set -ueo pipefail

if ! { ifconfig | grep -qF ::1; }; then
    export SKIP_IPv6_LOOPBACK_TESTS=
fi

: ${CONFIG:=library} # env CONFIG=dip1000 ./travis.sh

case "${BUILD_TOOL}" in
    meson)
      pip3 install --user --upgrade pip
      pip install --user --upgrade meson ninja
      meson builddir -Drun_test=true
      ninja -C builddir test
      ;;
    dub)
      dub test -c ${CONFIG}
      ;;
    *)
      echo 'Unknown build tool named: '"${BUILD_TOOL}"
      exit 1
      ;;
esac

if "${COVERAGE}"; then
    dub test -b unittest-cov -c ${CONFIG}
fi
