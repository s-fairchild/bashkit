# bashkit Style Guide

## Baseline: Google Shell Style Guide

All code in this repository follows the
[Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html).
Read it first. It is the default for every rule this document does not cover.

This document lists **only** the places where bashkit differs from Google,
or adds requirements Google doesn't have. If a rule is not listed here, the
Google guide applies unchanged. Some common examples:

- 2-space indentation, no tabs; 80-column lines.
- `[[ ]]` for tests.
  - Never `[ ]` or `test`.
- `(( ))`/`$(( ))` for arithmetic.
  - Never `let`, `$[ ]`, or `expr`.
- `$(...)` for command substitution, never backticks.
- Quote every expansion.
- Brace-delimit variables (`"${var}"`).
- Use arrays for lists of arguments.
  - Expand them quoted (`"${arr[@]}"`).
- No `eval` and no aliases.
- Declare function-scoped variables with `local`.
  - When the value comes from a command substitution, declare and assign
    separately (`local x; x="$(...)"`) so the exit status isn't masked.
  - If the value must not change afterwards, follow the assignment with
    `readonly x`.
- Send error messages to stderr.

Each section below says whether it is a **Difference** (it overrides a
Google rule) or an **Addition** (a bashkit-only requirement).

---

## 1. Files

### 1.1 File names — *Difference*

Google: source filenames are lowercase, with underscores to separate words.

bashkit: filenames are lowercase, with **hyphens** to separate words
(`contract-utils.sh`, `virsh-network.sh`, `local/bin/coreos-installer`).
Executables in `local/bin/` share their name with the binary they wrap.

Library files are named `<topic>-utils.sh` or `<dir>-<topic>.sh`. Each
library directory also has an **umbrella file** named after the directory
(`core/core.sh`, `virsh/virsh.sh`, …). It only sources every leaf file in
that directory.

### 1.2 First line — *Difference*

Google: executables start with `#!/bin/bash`.

bashkit:

| Kind | Location | First line | Executable bit |
| --- | --- | --- | --- |
| Library | `local/lib/bashkit/**/*.sh` | `# shellcheck shell=bash` | **No** |
| Wrapper executable | `local/bin/*` | `#!/bin/bash` | Yes |

Libraries have no shebang. They are only ever sourced, and the ShellCheck
directive tells linters which dialect to use.

### 1.3 File header comment — *Addition*

Google asks for a top-of-file comment. bashkit also fixes where it goes. It
comes right after the first line, with a blank `#` line between them:

```bash
# shellcheck shell=bash
#
# Thin, operand-validated wrappers around `virsh` network subcommands.
```

Don't put the file's path in the header (`# hack/lib/podman/...`). Those
paths come from before the code was moved here, and they go stale.

### 1.4 File layout — *Addition*

Every file uses this order:

1. First line (§1.2) and header comment (§1.3).
2. The xtrace hook: `[[ "${XTRACE:-0}" -eq 1 ]] && set -x`
3. The double-inclusion guard (§2.1).
4. Module constants (§3.2). An optional `### Globals Start ###` /
   `### Globals End ###` banner can wrap them.
5. Function definitions.
6. The dependency-sourcing block (§2.2).
7. `local/bin/*` only: the entry-point guard (§6.1).

Libraries run no other top-level code.

---

## 2. Sourcing

### 2.1 Double-inclusion guards — *Addition*

Every sourced file declares a read-only guard variable near the top:

```bash
readonly __BASHKIT_LIB_<DIR>_<FILE>_SOURCED="true"   # local/lib/bashkit/<dir>/<file>.sh
readonly __BASHKIT_LIB_<DIR>_SOURCED="true"          # umbrella file <dir>/<dir>.sh
readonly __BASHKIT_BIN_<NAME>_SOURCED="true"         # local/bin/<name>
```

`<DIR>`, `<FILE>`, and `<NAME>` are the path parts in uppercase, with
hyphens turned into underscores (for example,
`__BASHKIT_CORE_CONTRACT_UTILS_SOURCED`).

Consuming repos check these names. **Never rename a guard** unless you update
every consumer at the same time.

### 2.2 Sourcing dependencies — *Addition*

- Source each dependency behind its guard.
  - Never assume a caller already loaded it:

    ```bash
    if [[ "${__BASHKIT_CORE_CONTRACT_UTILS_SOURCED:-}" != "true" ]]; then
      # shellcheck source=../core/contract-utils.sh
      . "${BASH_SOURCE[0]%/*}/../core/contract-utils.sh"
    fi
    ```

- Paths inside this repo are relative to the sourcing file, through
  `${BASH_SOURCE[0]%/*}`.
  - Never make them relative to the caller's CWD or a repo root.
- Prefer `.` over `source`.
  - In bash they are the same builtin and behave identically; `.` is just
    the POSIX spelling and matches the existing code.
  - `source` is not wrong and isn't a review blocker.
- A `.`/`source` line whose path isn't static needs a
  `# shellcheck source=<relative path>` directive right above it.
  - Without one, ShellCheck can't follow the file and reports
    [SC1090](https://www.shellcheck.net/wiki/SC1090).
  - Every in-repo path starts with `${BASH_SOURCE[0]%/*}/` (see above), so
    in practice nearly every sourcing line needs the directive.
  - A fully static path doesn't need one, but those should be rare here.
- The logging library (`bash-logger`) lives outside this repo.
  - A file that uses any `core::*` contract helper (`core::fail`,
    `core::require_*`, …) sources `core/contract-utils.sh` and does **not**
    load `bash-logger` itself. `contract-utils.sh` loads the logger.
  - Only a file with no `core::` dependency loads the logger itself. It does
    so through `core/logger-utils.sh`, never by sourcing `logging.sh` by
    path:

    ```bash
    if [[ "${__BASHKIT_LIB_CORE_LOGGER_UTILS_SOURCED:-}" != "true" ]]; then
      # shellcheck source=../core/logger-utils.sh
      . "${BASH_SOURCE[0]%/*}/../core/logger-utils.sh"
    fi

    core::logger_init --name "$(basename "$0")"
    ```

  - `core::logger_init` does nothing if `init_logger` is already defined.
    Otherwise it sources the first `logging.sh` it finds in
    `vendor/bash-logger/`, `~/.local/lib/bash-logger/`, then
    `/usr/local/lib/bash-logger/`.
  - It passes `init_logger` the config file the environment selects
    (`BASHKIT_LOG_CONFIG`, `BASHKIT_ENV`; see `core::logger_config_path`).
  - It passes `--log "${BASHKIT_LOG_FILE}"` when that variable is set.
    Shipped `.bashkit/` configs don't set `log_file`: bash-logger requires
    an absolute path there, and consumers would inherit it.
  - It always routes every level to stderr (`--stderr-level DEBUG`), so log
    lines never end up in a caller's `$(...)` capture. A config file can't
    override this.

---

## 3. Naming

### 3.1 Function names — *Difference*

Google allows `::` package separators but doesn't require them. In bashkit,
every public function **must** be namespaced after its library directory:

```
core::*  ignition::*  k3s::*  kube::*  openssl::*  podman::*  virsh::*
```

After the `::` comes lowercase `snake_case`, ordered as noun then verb
(`virsh::net_define`, `podman::secret_exists`, `k3s::token_gen`).

- **Predicates**, which answer through their exit status, are named
  `<ns>::<noun>_is_<state>` or `<ns>::<noun>_exists`.
- **Usage printers** are named `<ns>::usage_<function-suffix>`.
- **Exception:** a wrapper executable's functions may reuse the wrapped
  binary's name, hyphens included.
  - For example, `core::coreos-installer` and `core::usage_coreos-installer`.

### 3.2 Constants and globals — *Difference*

Google: constants and exported variables are `UPPER_SNAKE_CASE`.

bashkit adds prefixes, because libraries share one global namespace with
their consumers:

- Module-private constants start with `__BASHKIT_` plus the module.
  - For example, `__BASHKIT_VIRSH_NETWORK_KEY_ACTIVE`.
- Declare them with `readonly`, or `declare -r` inside a function.
- Don't define new unprefixed globals.
  - The `ERROR_*`, `LOG_LEVEL_*`, and `BOOLEAN_*` names come from the
    external logging library, and bashkit only reads them.
- User-facing tunables are unprefixed environment variables that are read
  only.
  - For example, `XTRACE` and `PODMAN_LOG_LEVEL`.
- Always read a tunable with a default, like `${VAR:-}`.

---

## 4. Functions

### 4.1 Function comments — *Difference*

Google: comment a function unless it is both obvious and short. Wrap the
header in `#######` banner lines.

bashkit:

- **Every** function gets a header comment, however short.
- Don't use `#######` banners.
- Start the header with a signature line naming the function and its
  operands.
- Include all five sections.
  - Write `None.` for a section that doesn't apply.
- List arguments as `$N` or `-flag`, followed by an aligned description.

```bash
# core::is_option_arg_dup(opt current_value)
#
# Rejects a repeated single-value getopts flag. Call it from a
# `case "$opt" in ...)` arm *before* assigning `OPTARG`, passing the target
# variable's current (pre-assignment) value as <current_value> -- a
# non-empty value there means the flag was already seen once.
#
# Globals:
#   ERROR_OPTION_ARG_DUP
# Arguments:
#   $1   The option letter/flag being parsed.
#   $2   The target variable's current value, prior to this OPTARG
#        assignment.
# Outputs:
#   An error if the flag is a duplicate.
# Returns:
#   1 if the flag is a duplicate; 0 otherwise.
core::is_option_arg_dup() {
```

**Exception:** a `usage_*` function only needs the signature line and a
one-line description.

A long `Globals:` list may go past 80 columns. You can also wrap it, one or
more names per line.

### 4.2 Entry logging — *Addition*

The first statement of every function logs that the function started:

```bash
log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
```

Leave a blank line after it. Three cases need something different:

- If any operand may carry sensitive information, drop `$(IFS=' '; echo "$*")`
  from the line.

  ```bash
  log_debug "Starting ${FUNCNAME[0]}()"
  ```
  - For example: tokens, passwords, keys, secret specs, or file contents.
  - `log_debug` output and xtrace aren't safe places for secrets (§5).
  - Log an empty operand list: `log_debug "Starting ${FUNCNAME[0]}()"`.
  - Or list only the safe operands and redact the rest:
    `log_debug "Starting ${FUNCNAME[0]}(<config_json redacted> $2 $3)"`.
  - If the full operands are needed for debugging, log them on a separate
    line with `log_sensitive`: `log_sensitive "${FUNCNAME[0]}() options: $*"`.
    - Redirect it to stderr with `1>&2` in the same cases as the entry line.
- If the function's stdout is its return value, send this line to stderr
  with `1>&2`.
  - That is, when callers capture its output with `$(...)`.
  - bashkit's own logger setup already sends every level to stderr (§2.2).
    A consumer may set up the logger differently, though, so keep the
    redirect.
- In `local/bin/*` wrappers, wrap the line in
  `if declare -f log_debug >/dev/null 2>&1; then ... fi`.
  - Wrappers may run without the logger loaded.

### 4.3 Operand validation — *Addition*

Check required positional operands with `core::require_operands`, and then
copy them into read-only locals:

```bash
core::require_operands 2 "$@" || return
local -r network="$1"
local -r search="$2"
```

- `|| return` is required.
  - `core::require_operands` only returns from itself, not from its caller.
  - Use a bare `|| return`, not `|| return 1`, after every `core::require_*`
    check and every `core::fail` call. The caller then passes on whatever
    status the helper produced instead of hardcoding one.
- Don't use `${1?...}` or `${1?$(log_fatal ...)}` in new code.
- Give optional operands a default.
  - For example, `local -r desc="${2:-}"`.
- When getopts is used, parse options before checking operands.
  - Run `shift $((OPTIND - 1))`, and then call `core::require_operands`.

### 4.4 Option parsing — *Addition*

Functions that take flags parse them with getopts, in this form:

```bash
local opt OPTIND=1
while getopts ':l:h' opt; do
  case "${opt}" in
    h) <ns>::usage_<fn>; return 0 ;;
    l) labels+=("${OPTARG}") ;;
    :) <ns>::usage_<fn>; log_error "-${OPTARG} ${ERROR_OPTION_ARG_REQUIRED}"; return 1 ;;
    ?) <ns>::usage_<fn>; log_error "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"; return 1 ;;
  esac
done
shift $((OPTIND - 1))
```

- Start the optstring with `:`.
  - getopts then reports errors silently and the code handles them.
- Declare `OPTIND=1` as `local`.
  - This lets the function be called again.
- Collect repeatable flags into an array.
- For single-value flags, call `core::is_option_arg_dup` before assigning.
- Usage text is a `cat <<USAGE >&2` heredoc inside a `<ns>::usage_<fn>`
  function.

### 4.5 Returning versus exiting — *Addition*

Library functions `return` and never `exit`. `log_fatal` is only for states
that can't be recovered from. For bad input or a failed command, call
`core::fail` and return its status, so the caller decides what happens:

```bash
[[ -n "${input}" ]] || { core::fail "input cannot be empty string." || return; }
```

- `core::fail "<msg>"` logs `<caller>(): <msg>` at ERROR level, prints a
  stack trace (`core::print_stack_trace`), and returns 1.
  - Don't repeat the function name in `<msg>`. `core::fail` adds it.
- Always follow it with `|| return` (§4.3), even inside a `case` arm.
  - Write `core::fail "..." || return`, not `core::fail "..."; return`.
- Use it instead of a `log_error` + `return 1` pair.
  - Exception: code that must work before the logger is loaded (the
    functions in `core/logger-utils.sh`) uses `echo ... >&2`,
    `core::print_stack_trace`, and `return 1` instead.
    - `core::print_stack_trace` lives in `logger-utils.sh` for this reason.
      That file must not source anything, including `contract-utils.sh`.
  - Exception: getopts error arms (§4.4), which print usage and don't need a
    stack trace.

The one place `exit` is allowed is the `-h` branch of a `local/bin/*` wrapper
that runs as a script.

### 4.6 Surviving the caller's shell options — *Addition*

Consumers may run with `set -euo pipefail` and an `ERR` trap, so every
function has to survive those options:

- Read any variable that may be unset with a default: `${VAR:-}`.
- Don't end a function with `cond && cmd`.
  - When `cond` is false, the function returns non-zero.
  - Use `if cond; then cmd; fi` instead.
  - See §9 for the other rules on `&&`/`||` lists.
- Suppress an expected non-zero status explicitly with `|| true`.
  - Add a comment explaining why.
- Check every stage of a pipeline with `core::require_pipestatus`.
  - Call it as the very next command, because any other command overwrites
    `PIPESTATUS`.
  - Don't put `|| ...` on the pipeline itself. That runs a command and
    replaces `PIPESTATUS` before it can be checked.

  ```bash
  producer | consumer
  core::require_pipestatus "${PIPESTATUS[@]}" || return
  ```

### 4.7 Temporary files — *Addition*

**Avoid temporary files whenever possible.** Only create one when nothing
else works. A temp file touches the disk, can leak secrets (§5), and needs
cleanup that can fail. It can also collide with or leak into other runs.

Keep data in memory instead, in this order of preference:

| Need | In-memory method |
| --- | --- |
| Hold a value or a list | A variable or an array (`local -a`, `mapfile`/`readarray`) |
| Pass data to a command's stdin | A pipe, here-string (`<<< "${data}"`), or heredoc |
| A command that reads stdin when given `-` | Pipe into it with `-` as the file argument (e.g. `podman secret create ... -`) |
| A command that needs a file **path** it only reads once | Process substitution: `cmd <(printf '%s' "${data}")` |
| Capture a command's output | Command substitution: `x="$(cmd)"` |

A temp file is acceptable only when none of these work. For example:
- the command needs a seekable file, or reads the same file more than once;
- the command only writes its output to a path it's given;
- the data must outlive the function.

In the function comment, say why the temp file is needed.

When you do need one, create it with `mktemp`, never with a fixed name.
Clean it up with a trap on `RETURN`, not `EXIT`:

```bash
local tmp
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' RETURN
```

### 4.8 Input from an operand or stdin — *Addition*

A function that accepts its input as operands **or** on stdin checks the
operands first:

```bash
local input
if (( $# )); then
  input="$*"
elif [[ ! -t 0 ]]; then
  input="$(cat)"
else
  core::fail "input cannot be null." || return
fi
readonly input

[[ -n "${input}" ]] || { core::fail "input cannot be empty string." || return; }
```

- Test `(( $# ))` **before** `[[ ! -t 0 ]]`.
  - Under cron, ssh, podman, or CI, stdin is not a TTY even when nothing is
    piped in. Testing stdin first would ignore an explicit operand there.
- Take all operands (`"$*"`), not just `$1`.
- Reject empty input separately from missing input.
- Document the operands as `$@` in the function comment.

### 4.9 Wrappers and predicates — *Addition*

- A thin `virsh`/`podman` wrapper only validates operands and runs the real
  command.
  - Its return status is that command's status.
- Predicates (`*_is_*`, `*_exists`) print nothing and report only through
  their exit status.
  - This lets them be used directly in `if` or `&&`.
- Put container run options in a `local -a podman_run_options=(...)` array.
  - One option per line.
  - Pass them as `"${podman_run_options[@]}"`.

---

## 5. Logging and secrets — *Addition*

Google says to send errors to stderr. bashkit goes further and sends
**all** diagnostics through the bash-logger API:
`log_debug`, `log_info`, `log_warn`, `log_error`, `log_fatal`, and
`log_sensitive`.

- Don't use bare `echo ... >&2` for diagnostics.
  - Exception: code that runs before the logger can be loaded (the
    functions in `core/logger-utils.sh`).
  - Exception: `local/bin/*` fallbacks for when the logger isn't loaded.
- Log a variable's state with `log_debug "$(declare -p var)"`.
- Log anything that may contain secret material with `log_sensitive`, never
  with `log_debug` or `log_info`.
  - That includes secret specs, tokens, file contents, stdin input, and full
    podman option arrays.
- Turn off xtrace before a command whose expanded arguments are sensitive.
  - Use `core::with_xtrace_suppressed save <var>`, and restore it
    afterwards.
- Report a failed contract check with `core::fail` (§4.5), which also prints
  the stack trace.
  - `core::print_stack_trace` writes to stderr, so it is safe inside a
    function whose stdout is captured.

---

## 6. Executables (`local/bin/*`)

### 6.1 No `main`; source-or-run guard — *Difference*

Google: a script with any functions puts its logic in `main` and ends with
`main "$@"`.

bashkit wrappers can be run directly **or** sourced as a library (see
`core/bin-utils.sh`). So each wrapper defines a single namespaced entry
function and ends with this guard:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  core::yq "$@"
fi
```

Sourcing a wrapper must never have side effects beyond defining functions
and constants.

---

## 7. ShellCheck

### 7.1 Suppressions — *Addition*

Google doesn't cover ShellCheck directives. In bashkit:

- Only disable a check with a reason, written after a **second** `#`:

  ```bash
  # shellcheck disable=SC2034  # consumed by a script that sources this file
  ```

  - `-- reason` is invalid directive syntax.
- Don't disable SC2015, SC2068, SC2086, or SC2155.
  - Fix the code instead.
- Lint with ShellCheck as described in `.claude/skills/linting-code/SKILL.md`.

---

## 8. Small preferences — *Addition*

- Use `printf '%s' ...` instead of `echo` to write data.
  - `echo` is only for messages.
- Check whether a command exists with `command -v`, not `which`.
- Use `local -n` namerefs to pass arrays by name.
  - Document the parameter as a nameref in the function comment.
  - Validate the name with `core::require_nameref <name> [a|A|-]` before
    binding it.
  - Prefix the function's own locals (for example `__crn_name`) so they
    can't shadow the caller's variable. `core::require_nameref` can't detect
    that kind of shadowing.
- Break long pipelines with `\`.
  - Put `|` at the start of each continuation line, indented 2 spaces.

---

## 9. Chaining with `||` and `&&` — *Addition*

Google doesn't restrict `&&`/`||` lists. bashkit does, because bash gives
the two operators **equal precedence** and groups them left to right, so a
long unbraced chain rarely does what it looks like it does.

### 9.1 One operator per level; brace the rest

Each list has at most **one** `||` or `&&` at its top level. Wrap anything
after it in a brace group `{ ...; }`:

```bash
# Good
a || { b || c; }

# Bad
a || b || c
```

Both lines behave the same. The braced one makes the structure explicit:
"if `a` fails, try the fallback chain". Readers don't need to work out how
bash groups the operators.

A single operator needs no braces. For example, `core::require_operands 1
"$@" || return` and `[[ -n "${x}" ]] && y+=("${x}")` are fine. §4.6 still
applies: a function must not end with `cond && cmd`.

### 9.2 Never mix `&&` and `||` without braces

Bash parses `a || b && c` as `(a || b) && c`, so `c` runs whenever `a`
succeeds. That is almost never what was meant. Braces decide which command
`c` depends on:

```bash
# Good: c runs only when a fails and b succeeds.
a || { b && c; }

# Bad: c also runs when a succeeds.
a || b && c
```

### 9.3 `a && b || c` is not if-then-else ([SC2015](https://www.shellcheck.net/wiki/SC2015))

In `a && b || c`, `c` runs when `a` fails **or** when `b` fails. When you
mean "if `a`, then `b`, else `c`", write an `if`:

```bash
# Good
if a; then
  b
else
  c
fi

# Bad: c also runs if b fails.
a && b || c
```

Don't disable SC2015 (§7.1). Fix the code instead.

### 9.4 Brace groups, not subshells

Group with `{ ...; }`, never `( ... )`. A subshell swallows `return` and
`exit` and throws away variable assignments. So `a || ( core::fail "x" ||
return )` does **not** return from the function.

A short group fits on one line. Write the closing `;` before `}`, and put
`||` at the start of a continuation line:

```bash
[[ -f "${file}" ]] || { core::fail "file not found: ${file}" || return; }

core::is_option_arg_dup "${opt}" "${ignition}" \
  || { ignition::usage_serve; return 1; }
```

A longer group goes over several lines:

```bash
[[ -n "${test_output:-}" ]] || {
  core::fail "${yaml_file} - ${yaml_key} is empty string." \
    || return
}
```

---

## Appendix: known deviations in existing code

These files predate this guide. Fix them when you are editing them for
another reason. Don't copy their patterns.

| File | Deviation | Rule |
| --- | --- | --- |
| `podman/podman-{build,container,secret,volume}.sh` | Stale `# hack/lib/...` path header before the ShellCheck line | §1.2, §1.3 |
| `ignition/{butane,ignition-validate,serve}.sh` | Header comment comes before `# shellcheck shell=bash` | §1.2 |
| `local/bin/envsubst` | `# shellcheck shell=bash` instead of a shebang; lowercase guard `__bashkit_bin_envsubst_sourced` | §1.2, §2.1 |
| `podman/podman.sh` | Guard is `__LIB_PODMAN_SOURCED`, missing the `__BASHKIT_` prefix | §2.1 |
| `core/bin-utils.sh`, `core/yq-utils.sh`, `k3s/token-utils.sh`, `kube/{kube,kubectl,kustomize}.sh` | No file header comment | §1.3 |
| `core/yq-utils.sh` | No xtrace hook | §1.4 |
| `podman/podman-secret.sh` | `${1?...}` operand checks | §4.3 |
| `openssl/cert-utils.sh`, `podman/podman-secret.sh` | `local -r x="$(...)"` | Google (declare and assign separately) |
| `k3s/token-utils.sh` | `which`; function comment names don't match the functions (`k3s_gen_token*`) | §8, §4.1 |
| Several files | Function comments missing `Globals:` or other sections | §4.1 |
| `virsh/virsh-network.sh` | Dependency sourcing at the top of the file | §1.4 |
| `virsh/virsh-network.sh` (`virsh::net_define`) | Writes the network XML to a `mktemp` file with no stated reason. `virsh net-define <(printf ...)` may work instead; test it before changing | §4.7 |
| `core/sha512sum-utils.sh` | Function comments list arguments as `*) input - ...` instead of `$@` | §4.1 |
| `core/contract-utils.sh` (`core::fail`, `core::require_nameref`, `core::is_valid_var_name`) | Missing or partial function comments; no entry logging | §4.1, §4.2 |
| `kube/kubectl.sh` | `#######` banner comments; `kube::kubectl_wait` has no comment; `log_error` + `return 1` and `core::fail ...; return` instead of `core::fail ... \|\| return` | §4.1, §4.5 |
| `kube/kustomize.sh` | No function comments; unquoted `${cmd[@]}` behind `disable=SC2068` with no reason | §4.1, §7.1 |
