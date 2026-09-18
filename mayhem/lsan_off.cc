// Build-time LeakSanitizer off-switch (SPEC.md §6.2 item 15 / PORTING.md).
//
// `-fsanitize=address` always bundles LeakSanitizer in and there is no flag to keep ASan while
// dropping just leak detection, so the sanctioned hook is this TU, compiled with $SANITIZER_FLAGS
// and linked into the fuzzed binary. ASan and UBSan stay fully active; only leak reporting is off.
//
// It matters a lot for this target: STAR's genomeGenerate never frees its genome/suffix-array
// buffers before exit, so LSan reported ~1.5 GB "leaked" on essentially EVERY input — turning 100%
// of the seed corpus into crashers and drowning the real memory-safety findings. Leaks are also
// explicitly out of scope for this backport (the original mayhemheroes run 20 recorded 0
// memory/resource defects).
//
// This hook is the only sanctioned switch: the runtime enable/disable calls, a compiled-in default-
// options override and a Mayhemfile ASAN_OPTIONS are all forbidden, because Mayhem alone owns the
// runtime ASAN option set.
extern "C" int __lsan_is_turned_off() { return 1; }
