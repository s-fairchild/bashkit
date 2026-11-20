---
name: linting-code
description: >
  Lints the shell scripts in this bashkit repo (local/bin, local/lib/bashkit) using ShellCheck
  via `make lint` and the checked-in .shellcheckrc. Use whenever checking code quality or fixing
  lint errors here. This repo has no pre-commit, and its behavior tests run separately
  (`make test`) — see
  hack/vendor/bash-logger's own linting-code skill for a differently-configured sibling
  submodule; don't reuse its commands here.
---

# Linting Code (bashkit)

bashkit is a standalone, independently versioned library vendored as a git submodule. It has
one lint target, `make lint`, which runs ShellCheck over every shell file using the checked-in
`.shellcheckrc`, the files in `test/` included. There is no pre-commit config. Behavior tests
are separate: `make test` (see `CLAUDE.md`).

## Tools and where configuration lives

| Tool       | Checks                                           | Config                                    |
| ---------- | ------------------------------------------------- | ------------------------------------------ |
| ShellCheck | Shell syntax, quoting, portability, common bugs, plus the optional checks that enforce parts of `docs/STYLEGUIDE.md` | `.shellcheckrc` (repo root) |

`.shellcheckrc` sets `external-sources=true source-path=SCRIPTDIR check-sourced=true` and
enables these optional checks:

| Check | Code | Style rule |
| --- | --- | --- |
| `require-variable-braces` | SC2250 | `"${var}"` (Google baseline) |
| `require-double-brackets` | SC2292 | `[[ ]]`, never `[ ]` (Google baseline) |
| `deprecate-which` | SC2230 | `command -v`, not `which` (§8) |
| `check-extra-masked-returns` | SC2312 | Don't mask a `$(...)` or pipeline status (§4.6) |
| `quote-safe-variables` | SC2248 | Quote every expansion (Google baseline) |
| `avoid-nullary-conditions` | SC2244 | `[[ -n "${x}" ]]`, not `[[ "${x}" ]]` |

ShellCheck looks for `.shellcheckrc` starting in the linted file's directory and moving up, so
this file applies even when you lint from a consumer repo. It takes precedence over the
consumer's own rc file.

shfmt is deliberately **not** used. Its output conflicts with forms the style guide requires:
it splits the §4.2 entry-log line, one-line getopts `case` arms (§4.4), and one-line brace
groups (§9.4), and no flag keeps them.

## Commands

### Everything in one pass

```bash
make lint
```

### One file

```bash
shellcheck local/lib/bashkit/virsh/virsh-network.sh
```

### From a consuming repo

Run from that repo's root. bashkit's `.shellcheckrc` still applies:

```bash
shellcheck hack/vendor/bashkit/local/bin/* hack/vendor/bashkit/local/lib/bashkit/**/*.sh
```

### No SC1091 is expected

`core/logger-utils.sh` is the only file that sources the external logging library. Which copy it
finds depends on where bash-logger is installed, so its `# shellcheck source=` directive points at
`/dev/null`, and lint needs no submodule checked out. Every `SC1091` is a real finding: usually a
`# shellcheck source=` directive whose path, relative to the file it is in, doesn't exist.

### Confirm it actually behaves, not just parses

Only `os/bk-bootstrap.sh`, `array/contains.sh`, and the log-file selection in
`core/logger-utils.sh` have behavior tests so far (`make test`, `test/<dir>/<file>-test.sh`), plus
`test/lib/sourcing-test.sh`, which checks that every file can be sourced again without changing
anything. ShellCheck can't verify a function's runtime behavior (e.g. that
`core::require_operands` actually rejects a missing operand, or that a `virsh::*` wrapper
forwards its arguments correctly) — only that the shell syntax and common pitfalls are clean.
After ShellCheck passes, validate by sourcing `os/bk-bootstrap.sh` and importing the file once
`vendor/bash-logger` is initialized (see `CLAUDE.md`), or by writing a throwaway script that
defines stub versions of the logging API first (`init_logger`, `log_debug`/`log_info`/`log_warn`/
`log_error`/`log_fatal`/`log_sensitive`) — defining `init_logger` makes `core::logger_init` skip
loading bash-logger — then sources the bootstrap, imports the file, and calls the functions
directly. Don't source a library without the bootstrap: its `import` lines would run
ImageMagick's `import(1)`.

## Style rules

Style rules are not duplicated here. They live in `docs/STYLEGUIDE.md`: the
[Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) is the
baseline, and that file lists every bashkit-specific difference and addition. **Read it before
fixing findings.** Many ShellCheck fixes have a bashkit-preferred form, and a fix that
silences ShellCheck but breaks the style guide isn't done. The sections that matter most
when linting:

* Google baseline (top of the file): quoting, `local` vs. command substitution, arrays.
* §1.2: first line (`# shellcheck shell=bash` vs. shebang) and the executable bit.
* §2.2: `# shellcheck source=` directives on the `. /dev/null` line above every `import`, and on
  every other `.` line.
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
| SC2312 | `$(...)` or pipeline whose failure is masked | Split the command out and check its status, or append `\|\| true` with a comment explaining why (STYLEGUIDE §4.6) |
| SC1091 | Can't follow a sourced file                  | Not expected (see above). Check that the `# shellcheck source=` directive's path, relative to the file it is in, exists (STYLEGUIDE §2.2) |
