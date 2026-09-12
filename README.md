# bashkit

A standalone library of reusable bash functions and containerized-command
wrappers. There is no build step, package manifest, or test suite — every
file is plain bash, sourced directly or run as a wrapper executable.

`bashkit` is designed to be **vendored as a git submodule** into a consuming
project (e.g. under `hack/vendor/bashkit/`), sitting alongside a sibling
`bash-logger-adapter` submodule (e.g. `hack/vendor/bash-logger-adapter/`)
that supplies the logging/error API every file here depends on:

- `log_debug`, `log_info`, `log_warn`, `log_error`, `log_fatal`, `log_sensitive`
- `core::require_operands`, `ERROR_*` constants, a `fatal()` helper

Every file inside this repo sources its own siblings via
`${BASH_SOURCE[0]%/*}/<relative-path>`, so `local/bin/*` wrappers and
`local/lib/bashkit/**/*.sh` libraries work correctly regardless of the
caller's CWD — including once installed standalone to `~/.local`. The one
exception is the dependency *out* of this repo: each umbrella/leaf file
falls back to sourcing `bash-logger-adapter/adapter.sh` (or `logging.sh`) at
a fixed relative offset when the logging functions aren't already defined,
which assumes the sibling-submodule vendoring layout described above.

## Structure

```
local/
  bin/                          # standalone wrapper executables (source+run in one file)
    bw                          # flatpak run --command=bw com.bitwarden.desktop wrapper
    coreos-installer            # runs quay.io/coreos/coreos-installer:release via podman
    envsubst                    # runs docker.io/steve51516/envsubst:latest via podman
    yq                          # runs docker.io/mikefarah/yq via podman
  lib/bashkit/
    core/
      core.sh                   # umbrella loader for this directory
      bin-utils.sh               # sources local/bin/{bw,coreos-installer,yq} for library-style use
      contract-utils.sh          # core::require_operands, core::is_option_arg_dup,
                                  # core::is_boolean, core::with_xtrace_suppressed,
                                  # core::print_stack_trace, core::init_git_submodules_error
      file-utils.sh               # core::file_read_builtin, core::file_read_preserve_newlines,
                                  # core::file_parse_extension
      sha512sum-utils.sh          # core::sha512sum wrapper + core::checksum_parse_hash
    ignition/
      ignition.sh                # umbrella loader for this directory
      butane.sh                  # ignition::butane — runs butane in a container
      merge.sh                   # ignition::gen and friends — compiles butane -> ignition JSON,
                                  # inlines merge[] entries with verification hashes
      ignition-validate.sh        # ignition::validate — runs ignition-validate in a container
      serve.sh                   # ignition::serve — containerized nginx server for serving
                                  # ignition configs over HTTPS
    k3s/
      k3s.sh                     # umbrella loader for this directory
      token-utils.sh              # k3s::token_gen{,_openssl,_tr,_shasum} — cluster token generation
                                  # with fallback chain
    openssl/
      openssl.sh                 # umbrella loader for this directory
      cert-utils.sh               # openssl::private_key_gen, openssl::self_signed_cert_gen
    podman/
      podman.sh                  # umbrella loader for this directory
      podman-container.sh         # podman::container — runs a nested podman sharing the host's
                                  # rootless graphroot volume
      podman-secret.sh            # podman::secret_{exists,create_replace_from_stdin,
                                  # create_from_file,showsecret,gen_file_secretsdata,filter_by_label}
      podman-volume.sh            # podman::volume_{exists,create,export_untar_stdout}
      podman-build.sh              # podman::build and helpers for driving podman-build(1)
    virsh/
      virsh.sh                   # umbrella loader for this directory
      virsh-domain.sh             # virsh::domain_{define,undefine,create,start,destroy,
                                  # autostart,is_defined,is_active}
      virsh-network.sh            # virsh::net_{define,activate,destroy,is_defined,is_active,
                                  # is_persistent,is_autostart,autostart,parse_info}
      virsh-pool.sh               # virsh::pool_{define,build,start,autostart,is_defined,is_active},
                                  # virsh::vol_{create,is_present}
```

Each subdirectory's `*.sh` umbrella file (`core.sh`, `podman.sh`, `virsh.sh`,
`ignition.sh`, `k3s.sh`) just sources every leaf file in that directory
behind a double-inclusion guard — source the umbrella file to pull in a
whole group, or a leaf file directly if you only need one piece.

## Installing

```bash
make install
```

Copies `local/bin/*` to `~/.local/bin/` and recursively copies
`local/lib/bashkit/**` to `~/.local/lib/bashkit/`, preserving subdirectory
structure. This still requires the `bash-logger-adapter` shim (see above) to
be resolvable at the relative offset each file expects, so the vendored
git-submodule layout — sourcing directly out of
`hack/vendor/bashkit/local/lib/bashkit/...` next to
`hack/vendor/bash-logger-adapter/` — is the primary supported way to consume
this repo.

## Conventions

Functions follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html):
2-space indentation, `[[ ]]` (never `[ ]`/`test`), quoted expansions, and a
Description/Globals/Arguments/Outputs/Returns comment block above every
function.

- Functions are namespaced by directory: `core::*`, `virsh::*`, `podman::*`,
  `ignition::*`, `k3s::*`, `openssl::*`.
- Every sourced file guards against double-inclusion with a
  `readonly __BASHKIT_LIB_<NAME>_SOURCED="true"` at the top, checked before
  re-sourcing a dependency — don't rename these without updating every call
  site across every consumer.
- Argument validation goes through `core::require_operands N "$@" || return 1`
  followed by `local -r x="$1"`, not manual `${1?...}` checks.
- Function entry is logged as the first line of every function:
  `log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"`.
- Anything that could contain secrets (podman `--secret` specs, tokens, file
  contents) is logged with `log_sensitive`, never `log_debug`/`log_info`.
- Thin `virsh`/`podman` wrappers just validate operands and exec the real
  command; `*_is_*` predicate functions parse `virsh ...-info` output and
  return via exit status for direct use in `if`/`&&`.
- A function-scoped temp file is cleaned up with `trap 'rm -f "$file"' RETURN`
  (not `EXIT`).
- Shell libraries (`local/lib/bashkit/**/*.sh`) are not executable; only
  `local/bin/*` wrapper executables are.

## Linting

There is no test harness (no bats, no `.shellcheckrc`, no pre-commit). Lint
with `shellcheck` directly — see `.claude/skills/linting-code/SKILL.md` for
the full command reference, including how to lint from within a consuming
repo (recommended, so its `.shellcheckrc` and sourced-file resolution apply)
versus standalone. Validate runtime behavior by sourcing the affected file
from within a consumer repo that has the `bash-logger-adapter` shim
available.
