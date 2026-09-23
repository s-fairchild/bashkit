# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`bashkit` (github.com:s-fairchild/bashkit.git) is a standalone library of reusable bash functions and containerized-command wrappers. It has its own git history and is consumed as a **vendored git submodule** by other projects (e.g. at `hack/vendor/bashkit/` inside the `forge` repo). There is no build step, package manifest, or test suite here; every file is plain bash, sourced directly or run as a wrapper executable.

## Style guide

**Read `docs/STYLEGUIDE.md` before writing or editing any code here.** It makes the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) the baseline and documents every bashkit-specific difference and addition (file naming, namespacing, guard variables, function comment format, operand validation, getopts pattern, logging/secrets, wrapper entry points). Its appendix lists existing files that don't yet conform — don't copy patterns from those. When a convention changes, update `docs/STYLEGUIDE.md` rather than duplicating rules here.

## Sourcing and paths

- Files inside this repo source their siblings **relative to their own location** via `${BASH_SOURCE[0]%/*}/<relative-path>`, so libs and `local/bin/*` wrappers work regardless of the caller's CWD. Never switch to CWD- or repo-root-relative paths.
- Every dependency is sourced behind its double-inclusion guard (`readonly __BASHKIT_LIB_<DIR>_<FILE>_SOURCED="true"`, `__BASHKIT_BIN_<NAME>_SOURCED` for wrappers). Consumers check these names — **never rename a guard** without updating every consumer.
- The one dependency *outside* this repo is the logging library, `bash-logger/logging.sh`, which supplies `init_logger`, `log_debug`/`log_info`/`log_warn`/`log_error`/`log_fatal`/`log_sensitive`, and the `ERROR_*`/`BOOLEAN_*` constants. Files load it only if `init_logger` isn't already defined, from a fixed offset that assumes a sibling submodule layout:
  - libs: `${BASH_SOURCE[0]%/*}/../../../../../bash-logger/logging.sh` (i.e. `<vendor>/bash-logger/` next to `<vendor>/bashkit/`)
  - `local/bin/*`: `${BASH_SOURCE[0]%/*}/../../../../vendor/bash-logger/logging.sh`

  So nothing here can be sourced standalone from this checkout — test from within a consumer repo that has `bash-logger` vendored alongside.

## Structure

```
local/
  bin/                  # wrapper executables; runnable directly OR sourceable (see core/bin-utils.sh)
    bw                  # flatpak Bitwarden CLI passthrough
    coreos-installer    # quay.io/coreos/coreos-installer via podman (getopts -s secret / -m mount)
    envsubst            # envsubst via podman
    yq                  # docker.io/mikefarah/yq via podman
  lib/bashkit/
    core/               # core::*  — contract-utils (require_operands, is_option_arg_dup, is_boolean,
                        #            with_xtrace_suppressed, print_stack_trace), file-utils,
                        #            sha512sum-utils, yq-utils, bin-utils (sources local/bin/*)
    ignition/           # ignition::* — butane, merge (butane -> ignition JSON), validate, serve
    k3s/                # k3s::*   — cluster token generation
    openssl/            # openssl::* — private key / self-signed cert generation
    podman/             # podman::* — container, secret, volume, build helpers
    virsh/              # virsh::* — domain, network, pool/volume wrappers and *_is_* predicates
```

Each directory has an umbrella file named after it (`core/core.sh`, `virsh/virsh.sh`, …) that just sources every leaf file in that directory behind its guard. Add new leaf files to the umbrella. Functions are namespaced by directory (`<dir>::<noun>_<verb>`).

## Install

- Guard every sourced file against double-inclusion: `declare -r __vendor_bashkit_lib_<name>_sourced="true"` at the top, checked before re-sourcing dependencies at the bottom (each file re-sources `bash-logger-adapter/adapter.sh` and `core/contract-utils.sh` itself — don't assume load order from a caller).
- Log function entry as the first line of every function: `log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"`.
- Argument validation is consistent across every file now: `virsh-domain.sh`, `virsh-network.sh`, and `virsh-pool.sh` all use `core::require_operands N "$@" || return` then `local -r x="$1"` (the migration off the older `local -r x="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"` pattern, referenced in older commit messages as "adopt require_operands", is complete). Use `core::require_operands` for any new function.
- Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html): 2-space indentation, `[[ ]]` (never `[ ]`/`test`), quote every expansion (`"${var}"`), split `local x; x=$(...)` rather than combining declare+assign from a command substitution, and a Description/Globals/Arguments/Outputs/Returns comment block (matching the format already used in `hack/vendor/bash-logger-adapter/adapter.sh`) above every function. This repo's own `.claude/skills/linting-code/SKILL.md` has the full checklist and lint commands — read it before making further changes here.
- Anything that could contain secrets (podman `--secret` specs, tokens, file contents) is logged with `log_sensitive`, never `log_debug`/`log_info` — keep that distinction when adding new call sites that touch credential material.
- Thin `virsh`/`podman` wrappers just validate operands and exec the real command — no output parsing beyond the `*_is_*` predicate functions, which grep/cut `virsh ...-info` output and return via exit status for use directly in `if`/`&&` conditionals.
- `virsh_net_define()` builds an XML string in an array, writes it to a `mktemp` file, and relies on `trap 'rm -f "$network_xml_file"' RETURN` for cleanup — follow this pattern (trap on `RETURN`, not `EXIT`) for any other function-scoped temp file.
```bash
make install
```

Copies `local/bin/*` to `~/.local/bin/` and recursively installs `local/lib/bashkit/**` (mode 644) into `~/.local/lib/bashkit/`, preserving subdirectories. The installed copies still need `bash-logger` resolvable at the relative offsets above, so the vendored-submodule layout remains the primary supported way to consume this repo.

## Linting and validation

There is no test harness (no bats, no `.shellcheckrc`, no pre-commit). Lint with `shellcheck` — the `linting-code` skill (`.claude/skills/linting-code/SKILL.md`) has the commands for linting from a consumer repo (recommended) versus standalone, and which `SC1091` findings to expect. Validate runtime behavior by sourcing the affected file from within a consumer repo that has `bash-logger` vendored, or behind a minimal stub of the logging API.
