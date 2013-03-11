#!/bin/sh
set -e -u
: ${TOPDIR:=$(cd "$(dirname "$0")" && pwd)}
: ${REPO:=repo}
: ${STRIP:=strip}
: ${GZIP:=gzip}
: ${BZIP2:=bzip2}
: ${XZ:=xz}
: ${AR:=ar}
: ${TAR:=tar}
: ${CURL:=curl}
: ${REPO_FLAGS:=}
: ${REPO_SYNC_FLAGS:=-j4}
: ${NO_SYNC:=}
: ${CURL_FLAGS:=}
: ${TOOLCHAIN_URL:=git://github.com/jld/linaro-android-toolchain-manifest.git}
: ${TOOLCHAIN_BRANCH:=b2g}
: ${LINUX_URL:=git://github.com/jld/linux}
: ${LINUX_BRANCH:=b2g}
: ${DEBIAN_DIST:=unstable}
: ${DEBIAN_MIRROR:=http://ftp.us.debian.org/debian}

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
: ${LINUX_MAKE_FLAGS:=$MAKE_FLAGS}

get_linux_src() {
    SRCDIR=$TOPDIR/src/linux
    if [ -d "$SRCDIR" ]; then
	if [ -z "$NO_SYNC" ]; then
	    cd "$SRCDIR"
	    git remote set-url origin "$LINUX_URL"
	    git checkout -B "$LINUX_BRANCH" origin/"$LINUX_BRANCH"
	    git pull --ff-only
	fi
    else
	git clone -b "$LINUX_BRANCH" "$LINUX_URL" "$SRCDIR"
    fi
}

get_toolchain_src() {
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
    if [ -z "$NO_SYNC" ]; then
	"$REPO" $REPO_FLAGS sync $REPO_SYNC_FLAGS
    fi
}

maybe_fetch() {
    local url=$1 file=$2
    if ! [ -e "$file" ]; then
	"$CURL" $CURL_FLAGS -o "$file" "$url"
    elif [ -z "$NO_SYNC" ]; then
	"$CURL" $CURL_FLAGS -z "$file" -o "$file" "$url"
    fi
}

make_debian_sysroot() {
    TMPDIR=$TOPDIR/obj/debian-armel
    TARGET_SYSROOT=$TMPDIR/root
    TARGET_ARCH=armel
    TARGET_TRIPLE=arm-linux-gnueabi
    mkdir -p "$TARGET_SYSROOT"
    dist_main=$DEBIAN_MIRROR/dists/$DEBIAN_DIST/main
    packages_url=$dist_main/binary-$TARGET_ARCH/Packages.bz2
    packages_file=$TMPDIR/Packages.bz2
    maybe_fetch "$packages_url" "$packages_file"
    # FIXME: authenticate that blob
    "$BZIP2" -cd "$packages_file" | awk '
        $1 == "Package:" { p = $2 }
        $1 == "Filename:" && p ~ /^(libc6(-dev)?|linux-libc-dev)$/ { print $2 }
    ' | while read relpath; do
	deb_file=$TMPDIR/${relpath##*/}
	maybe_fetch "$DEBIAN_MIRROR/$relpath" "$deb_file"
	data_tar=$("$AR" t "$deb_file" | grep '^data\.tar\.' | head -1)
	case $data_tar in
	    *.gz) compressor=$GZIP ;;
	    *.bz2) compressor=$BZIP2 ;;
	    *.xz) compressor=$XZ ;;
	    *) echo "Unknown compression for $data_tar" >&2; exit 1 ;;
	esac
	ar p "$deb_file" "$data_tar" | "$compressor" -cd | \
	    ( cd "$TARGET_SYSROOT" && tar xvf - )
    done
    for x in 1 i n; do
	ln -nfs "$TARGET_TRIPLE/crt$x.o" "$TARGET_SYSROOT/usr/lib/crt$x.o"
    done
}

print_sources() {
    set +x
    local pfx=${1:-} subdir hash url branch
    while read subdir hash url branch; do
	if [ "$branch" = "$hash" ]; then
	    branch=""
	fi
	cat <<EOT
    $pfx$subdir:
        Repository: $url
        ${branch:+Branch: $branch
        }Revision: $hash

EOT
    done
    set -x
}

set -x
# FIXME: handle multiple arguments
case "${1:-all}" in
    all)
	"$0" toolchain-4.4.3
	"$0" perf
	"$0" target-perf
	"$0" SOURCES
	;;
    toolchain-4.4.3)
	get_toolchain_src
	cd "$SRCDIR/build"
	rm -rf "$PREFIX"
	mkdir "$PREFIX"
	if [ -r Makefile ]; then
	    # If a build is interrupted it can break the next build.
	    make $TOOLCHAIN_MAKE_FLAGS distclean || true
	fi
	LINARO_BUILD_EXTRA_CONFIGURE_FLAGS=-disable-graphite \
	    LINARO_BUILD_EXTRA_MAKE_FLAGS=$TOOLCHAIN_MAKE_FLAGS \
	    ./linaro-build.sh --with-gcc=gcc-4.4.3 \
	    --prefix="$PREFIX"
	;;

    perf)
	get_linux_src
	# FIXME: do this in a less bad way
	case $(uname -ms) in
	    "Linux x86_64") TRIPLE=x86_64-linux-gnu ;;
	    "Linux i686") TRIPLE=i686-linux-gnu ;;
	    *) echo "Unknown platform: $(uname -ms)" >&2; exit 1 ;;
	esac
	OBJDIR=$TOPDIR/obj/perf-$TRIPLE
	DSTBIN=$TOPDIR/perf/$TRIPLE-perf
	cd "$SRCDIR/tools/perf"
	mkdir -p "$OBJDIR"
	make $LINUX_MAKE_FLAGS O="$OBJDIR"
	"$STRIP" -o "$DSTBIN" "$OBJDIR/perf"
	;;

    target-perf)
	get_linux_src
	make_debian_sysroot
	cd "$SRCDIR/tools/perf"
	REAL_TARGET_TRIPLE=arm-linux-androideabi
	OBJDIR=$TOPDIR/obj/perf-$TARGET_TRIPLE
	DSTBIN=$TOPDIR/perf/$REAL_TARGET_TRIPLE-perf
	cd "$SRCDIR/tools/perf"
	mkdir -p "$OBJDIR"
	make $LINUX_MAKE_FLAGS ARCH=arm O="$OBJDIR" \
	    CROSS_COMPILE="$TOPDIR"/toolchain-4.4.3/bin/arm-linux-androideabi- \
	    NO_LIBELF=1 NO_NEWT=1 \
	    CFLAGS="--sysroot=$TARGET_SYSROOT \
                -isystem =/usr/include -isystem =/usr/include/$TARGET_TRIPLE \
                -DHAVE_ON_EXIT -mno-android -march=armv7-a -mfloat-abi=softfp \
                -Os" \
	    LDFLAGS="-L $TARGET_SYSROOT/usr/lib \
                 -L $TARGET_SYSROOT/usr/lib/$TARGET_TRIPLE \
                 -static"
	"$STRIP" -o "$DSTBIN" "$OBJDIR/perf"
	;;

    SOURCES)
	NO_SYNC=t # Want to make sure we use the same revs as what's here.
	# FIXME: that is not the right solution for that.
	DSTTXT=$TOPDIR/SOURCES
	cat > "$DSTTXT" <<EOT
Sources for this prebuilt toolchain can be downloaded from their
corresponding Git repositories.

For the files in the "perf" directory:

EOT
	get_linux_src
	cd "$SRCDIR"
	echo src/linux `git rev-parse HEAD` "$LINUX_URL" "$LINUX_BRANCH" \
	    | print_sources >> "$DSTTXT"

	tc=toolchain-4.4.3
	cat >> "$DSTTXT" <<EOT
For the files in the "$tc" directory:

EOT
	get_toolchain_src
	cd "$SRCDIR"
	repo forall -c 'git remote -v | \
          awk "\$1==\"$REPO_REMOTE\"&&\$3~/fetch/{\
            print\"$REPO_PATH\",\"$REPO_LREV\",\$2,\"$REPO_RREV\"}"' \
	    | print_sources "src/$tc/" >> "$DSTTXT"
	;;

    *)
	echo "Unknown buildable $1" >&2
	exit 1
esac
