---
name: linting-code
description: >
  Lints the shell scripts in this bashkit repo (local/bin, local/lib/bashkit) using ShellCheck.
  Use whenever checking code quality or fixing lint errors here. This repo has no
  .shellcheckrc, no pre-commit, and no test harness of its own — see hack/vendor/bash-logger's
  own linting-code skill for a differently-configured sibling submodule; don't reuse its
  commands here.
---

# Linting Code (bashkit)

Adapted from the consuming `forge` repo's `hack/.claude/skills/linting-code/`. That skill
assumes a repo-root Makefile (`lint-hack`/`lint-hack-file` targets) and a checked-in
`.shellcheckrc` — neither exists in this repo. bashkit is a standalone, independently
versioned library vendored as a git submodule; it has no Makefile lint targets, no
pre-commit config, and no test suite (see `CLAUDE.md` "No tests"). This skill covers what
actually exists here: running `shellcheck` directly.

## Tools and where configuration lives

| Tool       | Checks                                           | Config                                    |
| ---------- | ------------------------------------------------- | ------------------------------------------ |
| ShellCheck | Shell syntax, quoting, portability, common bugs  | None checked in — invoke with explicit flags (see below) |

There is no `.shellcheckrc` in this repo. When linting bashkit files *from within a consuming
repo* that does have one (e.g. `forge`'s `.shellcheckrc`, which sets `external-sources=true
source-path=SCRIPTDIR check-sourced=true`), that config is picked up automatically and is the
easiest way to get a clean, source-aware run — see "From a consuming repo" below. When linting
bashkit standalone (no consumer checkout), pass the equivalent flags explicitly.

## Commands

### From a consuming repo (recommended)

Run from that repo's root so its `.shellcheckrc` applies and sourced-file resolution matches
how these scripts are actually used:

```bash
shellcheck hack/vendor/bashkit/local/bin/coreos-installer
shellcheck hack/vendor/bashkit/local/lib/bashkit/**/*.sh hack/vendor/bashkit/local/lib/bashkit/*.sh
```

### Standalone (no consumer checkout)

```bash
shellcheck --external-sources --source-path=SCRIPTDIR --check-sourced <file>
```

`--check-sourced` still won't fully resolve every path: per `CLAUDE.md` ("Critical: paths are
relative to the *consumer's* CWD, not this repo"), every lib file's dependency paths assume a
sibling `hack/vendor/bash-logger-adapter/adapter.sh` one level up from wherever this repo is
vendored — that simply doesn't exist when linting this checkout on its own. Expect (and ignore)
`SC1091: Not following: ... openBinaryFile: does not exist` for the `bash-logger-adapter/
adapter.sh` and `options-operands-utils.sh` source lines when running this way; every other
finding is real.

### Everything in one pass

```bash
find local -name '*.sh' -o -path 'local/bin/*' -type f | xargs shellcheck
```

### Confirm it actually behaves, not just parses

There's no test harness. ShellCheck can't verify a function's runtime behavior (e.g. that
`require_operands` actually rejects a missing operand, or that a `virsh_*` wrapper forwards
its arguments correctly) — only that the shell syntax and common pitfalls are clean. After
ShellCheck passes, validate by sourcing the file from within a consumer repo that has the
`bash-logger-adapter/adapter.sh` shim available (see `CLAUDE.md`), or by writing a throwaway
script that sources the file behind a minimal fake shim (stub `debug`/`error`/`fatal`/
`require_operands`'s own dependencies, the `ERROR_*` constants) and calls the functions
directly — useful when the real adapter chain in a consumer repo isn't in a runnable state.

## Key rules — write clean code from the start

Based on [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html).
Every file here is bash-only (`# shellcheck shell=bash` or `#!/bin/bash`) — write to bash
idioms directly, not the lowest-common-denominator POSIX subset.

* **Indentation**: 2 spaces, never tabs.
* **Line length**: soft-wrap around 80 columns.
* **Quoting**: quote every expansion; prefer `"${var}"` over `"$var"` (brace-delimit unless
  it's a single-character shell special like `$?`/`$#`/`$$`/`$!`). Use a `local -a`/
  `declare -a` array for any list of command options/flags, expanded `"${arr[@]}"` — quoted —
  rather than an unquoted string; don't reach for `# shellcheck disable=SC2068` as a
  substitute for quoting correctly (`coreos-installer`'s `podman run "${podman_run_options[@]}"
  ... "$@"` is the pattern to match).
* **Conditionals**: `[[ ]]` everywhere, never `[ ]`/`test`/`/usr/bin/[`. Use `-z`/`-n` for
  string emptiness, `==` for string equality, `(( ))` for numeric comparisons, `[[ -v name ]]`
  to test whether a positional parameter/variable is set.
* **Command substitution**: `$(...)`, never backticks.
* **Arithmetic**: `(( ))` or `$(( ))` only — never `let` or `$[ ]`, never `expr`.
* **No `eval`**, no shell aliases (use a function instead).
* **Naming**: lowercase `snake_case` for functions and variables (the one deliberate exception
  is `coreos-installer`/`usage_coreos-installer`, which mirror the wrapped binary's own name).
  Constants and anything exported are `SCREAMING_SNAKE_CASE`, declared with `readonly`/`export`
  (or `declare -r`/`declare -rx`). Function-local variables use `local` (add `-r`/`-a`/`-A`/
  `-i` where it fits); split `local x` from `x=$(...)` when the value comes from a command
  substitution, so its exit status isn't masked and so a variable declared only in one
  conditional branch doesn't end up undeclared in another (see SC2155 below).
* **File header**: every file starts with a one-line (or short) description of what it
  contains, right after `# shellcheck shell=bash` / the shebang.
* **Function comments**: required for every function in this repo — Description, Globals,
  Arguments, Outputs, and Returns — matching the format already used in
  `hack/vendor/bash-logger-adapter/adapter.sh`'s own functions (a short `# name(args)` header
  line, a prose description, then labeled sections). Skip only a truly one-line, self-evident
  helper.
* Every sourced lib file guards against double-inclusion with a `declare -r
  __vendor_bashkit_lib_<name>_sourced="true"` (or, for the shared operands/getopts helper file,
  `__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced`) at the top — **do not
  rename these**: they're checked by every consumer across the parent repo's `hack/lib/*` and
  `hack/bin/*` before sourcing this file, so a rename breaks every one of those call sites (see
  `CLAUDE.md` "Critical: paths are relative to the *consumer's* CWD, not this repo").
* **Sourcing paths**: files inside this repo source siblings relative to their own location
  via `${BASH_SOURCE[0]%/*}/<relative-path>` (never relative to repo root) — this is what lets
  `local/bin/*` wrapper executables run correctly regardless of the caller's CWD, including
  when installed standalone to `~/.local/bin`. Preserve this convention; don't switch to
  repo-root-relative paths, which is the convention the *consuming* repo's own `hack/lib`/
  `hack/bin` use instead (see `CLAUDE.md`).
* Shell **libraries** (`local/lib/bashkit/**/*.sh`) must not be executable (`chmod -x`); only
  `local/bin/*` wrapper executables are.
* When suppressing a ShellCheck warning, add a reason with a second `#` — `# shellcheck
  disable=SCXXXX -- reason` is invalid directive syntax and fails to parse (SC1072/SC1073):

  ```bash
  # shellcheck disable=SC2034  # consumed by a script that sources this file
  ```

## Interpreting failures

Format: `file.sh:LINE:COL: severity: message [SCXXX]`. Look up unknown codes at
`https://www.shellcheck.net/wiki/SCXXX`.

Common in this repo:

| Code   | Cause                                        | Fix                                                          |
| ------ | --------------------------------------------- | -------------------------------------------------------------- |
| SC2086 | Unquoted variable                            | Wrap in `"$var"`                                              |
| SC1091 | Can't follow a sourced file                  | Expected/benign when linting standalone (see above); if it fires when linting from a consumer repo with `external-sources=true`, confirm the sibling file actually exists at the `${BASH_SOURCE[0]%/*}`-relative path |
| SC2155 | Combined `local`/assign masking exit status  | Split: `local x; x=$(...)`                                    |
| SC2068 | Unquoted `$@`/array expansion                | Quote it: `"$@"` / `"${arr[@]}"` — don't just disable the check |
