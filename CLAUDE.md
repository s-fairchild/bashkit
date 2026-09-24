# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`bashkit` (github.com:s-fairchild/bashkit.git) is a standalone library of reusable bash functions and containerized-command wrappers. It has its own git history and is consumed as a **vendored git submodule** by other projects (e.g. at `hack/vendor/bashkit/` inside the `forge` repo). There is no build step, package manifest, or test suite here; every file is plain bash, sourced directly or run as a wrapper executable.

## Style guide

**Read `docs/STYLEGUIDE.md` before writing or editing any code here.** It makes the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) the baseline and documents every bashkit-specific difference and addition (file naming, namespacing, guard variables, function comment format, operand validation, getopts pattern, logging/secrets, wrapper entry points). Its appendix lists existing files that don't yet conform — don't copy patterns from those. When a convention changes, update `docs/STYLEGUIDE.md` rather than duplicating rules here.

## Sourcing and paths

- Files inside this repo source their siblings **relative to their own location** via `${BASH_SOURCE[0]%/*}/<relative-path>`, so libs and `local/bin/*` wrappers work regardless of the caller's CWD. Never switch to CWD- or repo-root-relative paths.
- Every dependency is sourced behind its double-inclusion guard (`readonly __BASHKIT_LIB_<DIR>_<FILE>_SOURCED="true"`, `__BASHKIT_BIN_<NAME>_SOURCED` for wrappers). Consumers check these names — **never rename a guard** without updating every consumer.
- The one dependency *outside* this repo is the logging library, `bash-logger/logging.sh`, which supplies `init_logger`, `log_debug`/`log_info`/`log_warn`/`log_error`/`log_fatal`/`log_sensitive`, and the `ERROR_*`/`BOOLEAN_*` constants. Nothing sources it by path; files call `core::logger_init` from `core/logger-utils.sh`, which does nothing if `init_logger` is already defined and otherwise sources the first `logging.sh` it finds, in this order:
  1. `vendor/bash-logger/` — this repo's own submodule (`git submodule update --init`)
  2. `~/.local/lib/bash-logger/`
  3. `/usr/local/lib/bash-logger/`

  It then calls `init_logger --stderr-level DEBUG`, adding `--config <file>` when the environment picks one: `BASHKIT_LOG_CONFIG` (explicit path), else `logging-${BASHKIT_ENV}.conf`, else `logging.conf`. The first directory that has the file wins: `BASHKIT_LOG_CONFIG_DIR` (if set), this repo's `.bashkit/` (`dev`, `test`, `ci`, `staging`, `prod`), `${XDG_CONFIG_HOME:-~/.config}/bashkit`, `/usr/local/etc/bashkit`, then `/etc/bashkit`. Installed copies have no `.bashkit/` beside them, so they use the user and system directories. A `BASHKIT_ENV` with no matching file anywhere is a hard error. If `BASHKIT_LOG_FILE` is set it also passes `--log "${BASHKIT_LOG_FILE}"`; shipped configs never set `log_file`, because bash-logger requires it to be absolute and consumers would inherit it.
- bashkit only *reads* `BASHKIT_ENV` and `BASHKIT_LOG_FILE`; never set them inside a library. Development sets them through the committed `.envrc` (direnv, defaults to `dev`), CI through the workflow's `env:`, and consumers through their own environment. Anything that supplies a fallback uses `${BASHKIT_ENV:-default}`, so an outer value always wins.

## Structure

```
.bashkit/               # shipped bash-logger configs: logging-{dev,test,ci,staging,prod}.conf
.envrc                  # direnv: BASHKIT_ENV defaults to dev, BASHKIT_LOG_FILE to .log/${BASHKIT_ENV}.log
.log/                   # local log files; only its .gitignore is tracked
vendor/bash-logger/     # bash-logger submodule (the logging API every file depends on)
local/
  bin/                  # wrapper executables; runnable directly OR sourceable (see core/bin-utils.sh)
    bw                  # flatpak Bitwarden CLI passthrough
    coreos-installer    # quay.io/coreos/coreos-installer via podman (getopts -s secret / -m mount)
    envsubst            # envsubst via podman
    yq                  # docker.io/mikefarah/yq via podman
  lib/bashkit/
    core/               # core::*  — contract-utils (fail, require_operands, require_pipestatus,
                        #            require_nameref, is_option_arg_dup, is_boolean,
                        #            with_xtrace_suppressed), logger-utils (logger_source,
                        #            logger_config_path, logger_init, logger_resolve,
                        #            print_stack_trace; no dependencies), file-utils,
                        #            sha512sum-utils, yq-utils, bin-utils (sources local/bin/*)
    ignition/           # ignition::* — butane, merge (butane -> ignition JSON), validate, serve
    k3s/                # k3s::*   — cluster token generation
    kube/               # kube::*  — kubectl wait/apply/create/delete, kustomize build/build_apply
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

Copies `local/bin/*` to `~/.local/bin/` and recursively installs `local/lib/bashkit/**` (mode 644) into `~/.local/lib/bashkit/`, preserving subdirectories. It also copies `.bashkit/*.conf` into `${XDG_CONFIG_HOME:-~/.config}/bashkit/`, skipping any file already there so local edits survive (delete a file to get the shipped version again). Installed copies find `bash-logger` at `~/.local/lib/bash-logger/` or `/usr/local/lib/bash-logger/` (see *Sourcing and paths*); `make install` doesn't install it.

## Linting and validation

There is no test harness (no bats, no pre-commit). Lint with `make lint`, which runs `shellcheck` over every shell file using the checked-in `.shellcheckrc` — the `linting-code` skill (`.claude/skills/linting-code/SKILL.md`) explains the enabled optional checks, how to lint from a consumer repo, and which `SC1091` findings to expect. Validate runtime behavior by sourcing the affected file directly once `vendor/bash-logger` is initialized, or behind a minimal stub of the logging API.
