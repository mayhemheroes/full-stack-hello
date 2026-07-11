#!/usr/bin/env bash
# full-stack-hello/mayhem/build.sh — build `as_exec` (the "full stack hello world" toolchain: a tiny
# assembler + register VM) as the FILE-INPUT fuzz target, plus a clean normal-flags build of the same
# binary for the project's OWN golden-output test suite (mayhem/test.sh).
#
# full-stack-hello is a small C99 teaching project: driver.c parses argv, assemble_from_fd() (as.c)
# assembles a `.s` source read from a file descriptor into VM bytecode, then vm_run() (vm.c) executes
# it on a computed-goto interpreter; elf.c can also emit/load the bytecode as an ELF. The default mode
# (ASSEMBLE_AND_EVAL) takes one source file and assembles+runs it — exactly the old mayhemheroes
# integration's target (`as_exec /test.s`). The natural fuzz surface is the whole assemble+execute
# pipeline on a source file, so the Mayhem target is the `as_exec` binary itself on a file (CLI
# file-input, like lacc/hicolor) — there is no libFuzzer harness and thus no -standalone reproducer.
#
# Two builds from the same in-tree source (the Makefile builds `as_exec` in the repo root, and the
# .o files are shared, so the two builds can't coexist — build the test oracle first, stash it, clean,
# then the sanitized target):
#   (1) NORMAL-flags build -> /mayhem/build-tests/as_exec  (honest oracle for test.sh; no sanitizer noise)
#   (2) SANITIZED build     -> /mayhem/as_exec             (the file-input Mayhem target)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty
# value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the program's natural crash).
# as_exec links no external libraries, so the empty-sanitizer build links cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

SRCS="vm.c as.c opcode.c driver.c elf.c hash.c"

# opcode.h is GENERATED from opcode.def by scripts/gen_opcode.py (the Makefile's first build step).
# The base ships python; generate it once up front (both builds use the same header).
python scripts/gen_opcode.py opcode.h

# The project's Makefile passes -fno-crossjumping, a GCC-only flag that keeps GCC from merging the
# VM's computed-goto dispatch labels. clang (our $CC) doesn't accept it and never does that merge, so
# we simply omit it. -std=gnu99 matches the project (computed gotos are a GNU extension). -w silences
# the project's clean-build warnings (e.g. hash.c's `while (c = *str)`); they don't affect codegen.
BASE_CFLAGS="-std=gnu99 -w -g"

# ---------------------------------------------------------------------------
# (1) TEST build — the project's OWN flags, NO sanitizer. This is the honest oracle test.sh runs;
#     keeping it sanitizer-free avoids ASan/UBSan/LSan noise in the functional suite. The assembler/VM
#     is a run-once tool that intentionally doesn't free interned strings before exit, so a sanitized
#     oracle would otherwise report benign exit-time leaks. Stashed under build-tests/ before the
#     sanitized build reuses the shared .o files.
# ---------------------------------------------------------------------------
rm -f ./*.o as_exec
gcc $BASE_CFLAGS $DEBUG_FLAGS -fno-crossjumping -O2 -c $SRCS -I.
gcc $DEBUG_FLAGS -o as_exec ./*.o
mkdir -p "$SRC/build-tests"
cp -f as_exec "$SRC/build-tests/as_exec"
echo "build.sh: test-oracle as_exec -> $SRC/build-tests/as_exec"

# ---------------------------------------------------------------------------
# (2) FUZZ build — the assembler+VM compiled WITH $SANITIZER_FLAGS so the FUZZED CODE (the parser in
#     as.c, the interpreter in vm.c, the ELF reader in elf.c) is instrumented (ASan+UBSan, halting,
#     default). The file-input Mayhem target lands at /mayhem/as_exec.
#
#     We also link mayhem/asan_default_options.c, which bakes a weak __asan_default_options =
#     "detect_leaks=0" into the binary: as_exec is a run-once-per-input CLI that deliberately doesn't
#     free its interned operand strings / VM labels before exit (as.c:quoted_strdup, vm.c:vm_make_label,
#     …), so LeakSanitizer would fire on essentially EVERY input and bury the real memory-safety bugs.
#     (Only meaningful when ASan is in the flags; harmless otherwise. We do NOT set ASAN_OPTIONS in the
#     Mayhemfile — Mayhem owns the runtime option set; baking the default into the binary is the
#     supported way to turn leak detection off for fuzzing.) ASan's heap/stack/global OOB and
#     use-after-free checks, plus all of UBSan, stay ON and HALTING.
# ---------------------------------------------------------------------------
ASAN_OPTS_SRC=""
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  ASAN_OPTS_SRC="mayhem/asan_default_options.c"
fi

rm -f ./*.o as_exec
$CC $BASE_CFLAGS $SANITIZER_FLAGS $DEBUG_FLAGS -c $SRCS -I.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -o /mayhem/as_exec ./*.o ${ASAN_OPTS_SRC:+$ASAN_OPTS_SRC}

echo "build.sh: built /mayhem/as_exec (sanitized file-input fuzz target) and $SRC/build-tests/as_exec (test oracle)"
ls -l /mayhem/as_exec "$SRC/build-tests/as_exec"
