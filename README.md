=== Boot To Gecko Experimental Toolchain Prebuilt Binaries

This repository contains tools for ongoing work on Boot To Gecko /
Firefox OS.  Currently, this is mostly getting stack traces for
profiling, and support for Linux perf; see [bug 831631] and [bug
810526].

  [bug 831631]: (https://bugzilla.mozilla.org/show_bug.cgi?id=831611)
  [bug 810526]: (https://bugzilla.mozilla.org/show_bug.cgi?id=810526)

The file `build.sh` can rebuild all of the binaries here, but it has
to fetch approximately 2.5 GiB of source repositories, and it has some
dependencies (`repo`, anything Linux perf needs (for both amd64 and
x86), autotools, and probably more I'm forgetting).  This has also
only been tested on Linux; the toolchain might be hostable on other
Unix-like systems, but perf probably won't build at all on non-Linux,
even though tools like `perf report` don't actually need OS-specific
features.

Thus, this repository has the (much smaller) binaries, and a script to
rebuild them, and mostly-human-readable source code provenance
information in the file `SOURCES` (modeled after the one in the AOSP
(Android) prebuilt toolchain, which empirically seems to be sufficient
to prevent anyone from feeling deprived of their rights under the
GPL).
