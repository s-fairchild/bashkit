# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`bashkit` (github.com:s-fairchild/bashkit.git) is a standalone library of reusable bash functions and containerized-command wrappers. It has its own git history and is consumed as a **vendored git submodule** by other projects — in this checkout it lives at `hack/vendor/bashkit/` inside the `titan` repo (see `../../../../CLAUDE.md` for that project). There is no build step, package manifest, or test suite here; every file is plain POSIX-ish bash sourced directly.

## Critical: paths are relative to the *consumer's* CWD, not this repo

Every lib file's self-sourcing guard block hardcodes paths like:

```bash
declare __vendor_bash_logger_adapter="hack/vendor/bash-logger-adapter.sh"
declare __vendor_bashkit_utils_options="hack/vendor/bashkit/local/lib/bashkit/options.sh"
```

These are **not** `${BASH_SOURCE[0]%/*}`-relative — they assume the sourcing script is run from the consuming project's repo root, with bashkit vendored at exactly `hack/vendor/bashkit/` and a sibling `hack/vendor/bash-logger-adapter.sh` shim present. This repo cannot source its own libs standalone; a `log_debug`/`log_error`/`log_fatal`/`require_operands`/`ERROR_*` API and a `fatal()` helper must come from that external shim. When editing or adding a lib file here, preserve this convention (same guard-var naming and path shape) rather than switching to `$BASH_SOURCE`-relative sourcing — the latter would break every existing consumer.

## Install target has a known gap

```bash
make install
```
copies `local/bin/*` to `~/.local/bin/` and `local/lib/bashkit/*` to `~/.local/lib/bashkit/`. The lib copy uses `install -t ... local/lib/bashkit/*`, which does **not** recurse into subdirectories — `install` prints `omitting directory` and exits nonzero for `network/` and `virsh/`, so only the top-level `file-utils.sh`/`options.sh` actually land in `~/.local/lib/bashkit/`. Standalone installs are effectively broken for the `virsh/` and `network/` libs today; the vendored-submodule path (sourcing directly out of `hack/vendor/bashkit/local/lib/bashkit/...`) is the one that actually works and is what `titan` relies on.

## Structure

```
local/
  bin/                        # standalone wrapper executables (source+run in one file)
    bw                        # thin `flatpak run --command=bw com.bitwarden.desktop` wrapper
    coreos-installer           # runs quay.io/coreos/coreos-installer:release via podman
  lib/bashkit/
    file-utils.sh              # read_file_builtin, read_file_preserve_newlines, parse_file_extension
    options.sh                 # is_option_arg_dup, with_xtrace_suppressed getopts helpers
    network/validate.sh        # validate_url
    virsh/
      virsh-domain.sh          # virsh_dom_{define,undefine,create,start,destroy,autostart,is_defined,is_active}
      virsh-network.sh         # virsh_net_{define,activate,destroy,is_defined,is_active,is_persistent,is_autostart,autostart}
      virsh-pool.sh            # virsh_pool_{define,build,start,autostart,is_defined,is_active}, virsh_vol_{create,is_present}
```

`local/bin/coreos-installer` is a full argument-parsing wrapper (`getopts ':s:m:h'` for `-s` secret specs and `-m` mount specs) around `podman run` of the coreos-installer image, forwarding remaining args to the containerized binary. `local/bin/bw` is a one-line flatpak passthrough with no option parsing.

## Conventions to follow when adding/editing functions

- Guard every sourced file against double-inclusion: `declare -r __vendor_bashkit_lib_<name>_sourced="true"` at the top, checked before re-sourcing dependencies at the bottom (each file re-sources `bash-logger-adapter.sh` and `options.sh` itself — don't assume load order from a caller).
- Log function entry as the first line of every function: `log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"`.
- Argument validation is **inconsistent across files** — `virsh-domain.sh` and `virsh-network.sh` (newer, per `git log`) use `require_operands N "$@" || return 1` then `local -r x="$1"`; `virsh-pool.sh` (older) still uses the `local -r x="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"` pattern. When touching a file, match its existing pattern rather than mixing the two; when adding a new file, prefer `require_operands` (the direction the repo is migrating in, per recent commit "adopt require_operands").
- Anything that could contain secrets (podman `--secret` specs, tokens, file contents) is logged with `log_sensitive`, never `log_debug`/`log_info` — keep that distinction when adding new call sites that touch credential material.
- Thin `virsh`/`podman` wrappers just validate operands and exec the real command — no output parsing beyond the `*_is_*` predicate functions, which grep/cut `virsh ...-info` output and return via exit status for use directly in `if`/`&&` conditionals.
- `virsh_net_define()` builds an XML string in an array, writes it to a `mktemp` file, and relies on `trap 'rm -f "$network_xml_file"' RETURN` for cleanup — follow this pattern (trap on `RETURN`, not `EXIT`) for any other function-scoped temp file.

## No tests

There is no test harness (no bats, no shellcheck config beyond the `# shellcheck shell=bash` / `# shellcheck disable=...` directive comments already in each file). Validate changes by sourcing the affected file from within a consumer repo (e.g. `titan`) that has the `bash-logger-adapter.sh` shim available, or by running `shellcheck` directly against the file.
