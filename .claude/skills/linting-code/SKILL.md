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

`--check-sourced` still won't fully resolve every path. Every file falls back to sourcing the
external logging library at a fixed offset that assumes a sibling submodule layout (see
`CLAUDE.md` "Sourcing and paths"): `../../../../../bash-logger/logging.sh` from a lib file, or
`../../../../vendor/bash-logger/logging.sh` from `local/bin/*`. That file doesn't exist when
linting this checkout on its own. Expect (and ignore) `SC1091: Not following: ...
openBinaryFile: does not exist` for the `bash-logger/logging.sh` source lines when running this
way; every other finding is real.

### Everything in one pass

```bash
find local -name '*.sh' -o -path 'local/bin/*' -type f | xargs shellcheck
```

### Confirm it actually behaves, not just parses

There's no test harness. ShellCheck can't verify a function's runtime behavior (e.g. that
`core::require_operands` actually rejects a missing operand, or that a `virsh::*` wrapper
forwards its arguments correctly) — only that the shell syntax and common pitfalls are clean.
After ShellCheck passes, validate by sourcing the file from within a consumer repo that has
`bash-logger` vendored alongside bashkit (see `CLAUDE.md`), or by writing a throwaway script
that defines stub versions of the logging API first (`init_logger`, `log_debug`/`log_info`/
`log_warn`/`log_error`/`log_fatal`/`log_sensitive`, and whichever `ERROR_*`/`BOOLEAN_*`
constants the file reads) — defining `init_logger` skips the fallback source — then sources the
file and calls the functions directly.

## Style rules

Style rules are not duplicated here. They live in `docs/STYLEGUIDE.md`: the
[Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) is the
baseline, and that file lists every bashkit-specific difference and addition. **Read it before
fixing findings.** Many ShellCheck fixes have a bashkit-preferred form, and a fix that
silences ShellCheck but breaks the style guide isn't done. The sections that matter most
when linting:

* Google baseline (top of the file): quoting, `local` vs. command substitution, arrays.
* §1.2: first line (`# shellcheck shell=bash` vs. shebang) and the executable bit.
* §2.2: `# shellcheck source=` directives on every `.` line.
* §4.3: `core::require_operands` instead of `${1?...}`.
* §7.1: ShellCheck suppressions: when they're allowed and the reason syntax.
* §9: `&&`/`||` chaining: one operator per level, brace groups, no `a && b || c`.
* Appendix: files known to break the guide. Don't treat their patterns as precedent.

## Interpreting failures

Format: `file.sh:LINE:COL: severity: message [SCXXX]`. Look up unknown codes at
`https://www.shellcheck.net/wiki/SCXXX`.

Common in this repo:

| Code   | Cause                                        | Fix                                                          |
| ------ | --------------------------------------------- | -------------------------------------------------------------- |
| SC2086 | Unquoted variable                            | Quote and brace it: `"${var}"`. Don't disable (STYLEGUIDE §7.1) |
| SC2068 | Unquoted `$@`/array expansion                | Quote it: `"$@"` / `"${arr[@]}"`. Don't disable (STYLEGUIDE §7.1) |
| SC2155 | Combined `local`/assign masking exit status  | Split: `local x; x="$(...)"`. Don't disable (STYLEGUIDE §7.1) |
| SC2015 | `a && b \|\| c` used as if-then-else    | Rewrite as `if`/`else`, or brace the chain (STYLEGUIDE §9). Don't disable |
| SC1072/SC1073 | Malformed `# shellcheck` directive, usually `-- reason` | Put the reason after a second `#` (STYLEGUIDE §7.1) |
| SC1091 | Can't follow a sourced file                  | Expected when linting standalone (see above). If it fires when linting from a consumer repo with `external-sources=true`, check that the file exists at the `${BASH_SOURCE[0]%/*}`-relative path and that the `# shellcheck source=` directive matches it (STYLEGUIDE §2.2) |
