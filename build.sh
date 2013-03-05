#!/bin/sh
set -e -u
: ${TOPDIR:=$(cd "$(dirname "$0")" && pwd)}
: ${REPO:=repo}
: ${REPO_FLAGS:=}
: ${REPO_SYNC_FLAGS:=-j4}
: ${TOOLCHAIN_URL:=git://github.com/jld/linaro-android-toolchain-manifest.git}
: ${TOOLCHAIN_BRANCH:=b2g}

### Copied from B2G/config.sh
case `uname` in
"Darwin")
        CORE_COUNT=`system_profiler SPHardwareDataType | grep "Cores:" | sed -e 's/[ a-zA-Z:]*\([0-9]*\)/\1/'`
        ;;
"Linux")
        CORE_COUNT=`grep processor /proc/cpuinfo | wc -l`
        ;;
*)
        echo Unsupported platform: `uname`
        exit -1
esac

: ${MAKE_FLAGS:=-j$((CORE_COUNT + 2)) }
: ${TOOLCHAIN_MAKE_FLAGS:=$MAKE_FLAGS}

set -x
case "${1:-all}" in
    all)
	"$0" toolchain-4.4.3
	;;
    toolchain-4.4.3)
	SRCDIR=$TOPDIR/src/toolchain-4.4.3
	PREFIX=$TOPDIR/toolchain-4.4.3
	if [ -d "$SRCDIR" ]; then
	    cd "$SRCDIR"
	else
	    mkdir -p "$SRCDIR"
	    cd "$SRCDIR"
	    "$REPO" $REPO_FLAGS init -u "$TOOLCHAIN_URL" -b "$TOOLCHAIN_BRANCH"
	    NO_SYNC=
	fi
	if [ -z "${NO_SYNC:-}" ]; then
	    "$REPO" $REPO_FLAGS sync $REPO_SYNC_FLAGS
	fi
	cd build
	rm -rf "$PREFIX"
	mkdir "$PREFIX"
	if [ -r Makefile ]; then
	    # If a build is interrupted it can break the next build.
	    make distclean || true
	fi
	LINARO_BUILD_EXTRA_CONFIGURE_FLAGS=-disable-graphite \
	    LINARO_BUILD_EXTRA_MAKE_FLAGS=$TOOLCHAIN_MAKE_FLAGS \
	    ./linaro-build.sh --with-gcc=gcc-4.4.3 \
	    --prefix="$PREFIX"
	;;

    *)
	echo "Unknown buildable $1" >&2
	exit 1
esac


