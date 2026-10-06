# shellcheck shell=bash
#
# A small harness for bashkit's behavior tests. A test file sources it, calls
# test::suite_init, runs its cases, and ends with test::summary_print:
#
#   # shellcheck source=../test-utils.sh
#   . "$(dirname -- "${BASH_SOURCE[0]}")/../test-utils.sh"
#   test::suite_init || exit
#
#   test::case_run 'import: loads a sibling' 0 'helper' <<'CASE'
#   . "${TEST_BOOTSTRAP}"
#   import "${TEST_WORK}/app/helper"
#   helper_fn
#   CASE
#
#   test::summary_print
#
# A case is a bash script, read from stdin. It runs in a bash process and an
# empty working directory of its own, so cases can't affect each other or
# the harness. It can read these exported variables:
#
#   TEST_REPO        The bashkit checkout.
#   TEST_LIB         ${TEST_REPO}/local/lib/bashkit
#   TEST_BOOTSTRAP   ${TEST_LIB}/os/bk-bootstrap.sh
#   TEST_WORK        A scratch directory for fixtures, shared by the cases of
#                    one test file and removed when that file exits.
#
# The harness doesn't load any of bashkit itself: it has to work when the
# code under test doesn't.

readonly __BASHKIT_TEST_UTILS_SOURCED="true"

declare -gi __BASHKIT_TEST_COUNT=0
declare -gi __BASHKIT_TEST_PASSED=0
declare -gi __BASHKIT_TEST_FAILED=0
declare -gi __BASHKIT_TEST_SKIPPED=0
# The directory of the case test::case_run ran last.
declare -g __BASHKIT_TEST_CASE_DIR=""

# test::suite_init()
#
# Prepares a test file's run: resolves and exports the TEST_* variables,
# creates the scratch directory, and fixes the environment the cases see, so
# that the developer's own (direnv, CDPATH, verbosity) can't change a result.
# Logging goes to .log/test.log.
#
# Globals:
#   TEST_REPO, TEST_LIB, TEST_BOOTSTRAP, TEST_WORK   Set and exported.
#   BASHKIT_ENV, BASHKIT_LOG_FILE                    Set and exported.
#   BASHKIT_LOG_CONFIG, BASHKIT_LOG_CONFIG_DIR, BASHKIT_VERBOSE,
#   BASHKIT_QUIET, BASHKIT_LEVEL, CDPATH             Unset.
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   0 when the run is set up; non-zero when the checkout can't be resolved
#   or the scratch directory can't be created.
test::suite_init() {
  set -o nounset

  # Physical paths: the bootstrap records imported files by their physical
  # path, and cases compare against these.
  local path
  path="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)" || return
  TEST_REPO="${path}"
  TEST_LIB="${TEST_REPO}/local/lib/bashkit"
  TEST_BOOTSTRAP="${TEST_LIB}/os/bk-bootstrap.sh"

  path="$(mktemp -d "${TMPDIR:-/tmp}/bashkit-test.XXXXXX")" || return
  path="$(cd "${path}" && pwd -P)" || return
  TEST_WORK="${path}"
  trap 'test::_work_remove' EXIT

  readonly TEST_REPO TEST_LIB TEST_BOOTSTRAP TEST_WORK
  export TEST_REPO TEST_LIB TEST_BOOTSTRAP TEST_WORK

  unset -v CDPATH BASHKIT_LOG_CONFIG BASHKIT_LOG_CONFIG_DIR \
    BASHKIT_VERBOSE BASHKIT_QUIET BASHKIT_LEVEL
  export BASHKIT_ENV="test"
  export BASHKIT_LOG_FILE="${TEST_REPO}/.log/test.log"
}

# test::_work_remove()
#
# Removes the scratch directory. Runs as the test file's EXIT trap.
#
# Globals:
#   TEST_WORK
# Arguments:
#   None.
# Outputs:
#   None.
# Returns:
#   Always 0.
test::_work_remove() {
  if [[ -n "${TEST_WORK:-}" && -d "${TEST_WORK}" ]]; then
    rm -rf -- "${TEST_WORK}"
  fi
  return 0
}

# test::fixture_write(path)
#
# Writes stdin to <path> under the scratch directory, creating the
# directories on the way.
#
# Globals:
#   TEST_WORK
# Arguments:
#   $1   The file's path, relative to ${TEST_WORK}.
# Outputs:
#   None.
# Returns:
#   The status of `mkdir` or `cat`.
test::fixture_write() {
  local -r path="${TEST_WORK}/$1"

  mkdir -p "${path%/*}" || return
  cat > "${path}"
}

# test::case_run(name status stdout [stdin])
#
# Runs one case and prints whether it passed. The case's script is read from
# stdin and run with bash, in an empty directory, with <stdin> as its input.
# It passes when its exit status is <status> and its stdout is exactly
# <stdout>. A failed case is printed with what it returned and wrote.
#
# Globals:
#   TEST_WORK
#   __BASHKIT_TEST_CASE_DIR   Set to this case's directory.
#   __BASHKIT_TEST_COUNT, __BASHKIT_TEST_PASSED, __BASHKIT_TEST_FAILED
# Arguments:
#   $1   The case's name.
#   $2   The exit status the script must end with.
#   $3   The stdout the script must write, without its trailing newlines.
#        `*` accepts any.
#   $4   Optional. What the script reads on stdin. Defaults to nothing.
# Outputs:
#   One "ok" or "FAIL" line on stdout, and the details of a failure.
# Returns:
#   Always 0. The test file's status comes from test::summary_print.
test::case_run() {
  local -r name="$1"
  local -ri want_status="$2"
  local -r want_stdout="$3"
  local -r input="${4:-}"

  __BASHKIT_TEST_COUNT+=1
  __BASHKIT_TEST_CASE_DIR="${TEST_WORK}/case/${__BASHKIT_TEST_COUNT}"
  local -r dir="${__BASHKIT_TEST_CASE_DIR}"
  mkdir -p "${dir}/cwd"
  cat > "${dir}/case.sh"
  printf '%s' "${input}" > "${dir}/stdin"

  # The script sits beside the working directory, not in it, so that "beside
  # the calling script" and "in the working directory" are different places.
  local stdout
  local -i status=0
  stdout="$(
    cd "${dir}/cwd" \
      && timeout 60 bash "${dir}/case.sh" < "${dir}/stdin" 2> "${dir}/stderr"
  )" || status=$?
  readonly stdout status

  if (( status == want_status )) \
    && [[ "${want_stdout}" == '*' || "${stdout}" == "${want_stdout}" ]]; then
    __BASHKIT_TEST_PASSED+=1
    printf 'ok    %s\n' "${name}"
    return 0
  fi

  __BASHKIT_TEST_FAILED+=1
  printf 'FAIL  %s\n' "${name}"
  printf '      status: %s (want %s)\n' "${status}" "${want_status}"
  printf '      stdout: %q\n' "${stdout}"
  printf '      want:   %q\n' "${want_stdout}"
  sed 's/^/      stderr: /' "${dir}/stderr"
  return 0
}

# test::stderr_has(name pattern)
#
# Checks that the case test::case_run ran last wrote a line matching
# <pattern> to stderr.
#
# Globals:
#   __BASHKIT_TEST_CASE_DIR, __BASHKIT_TEST_PASSED, __BASHKIT_TEST_FAILED
# Arguments:
#   $1   The check's name.
#   $2   An extended regular expression, matched against each line.
# Outputs:
#   One "ok" or "FAIL" line on stdout, and the stderr of a failure.
# Returns:
#   Always 0.
test::stderr_has() {
  local -r name="$1"
  local -r pattern="$2"

  if grep -qE -- "${pattern}" "${__BASHKIT_TEST_CASE_DIR}/stderr"; then
    __BASHKIT_TEST_PASSED+=1
    printf 'ok    %s\n' "${name}"
    return 0
  fi

  __BASHKIT_TEST_FAILED+=1
  printf 'FAIL  %s\n      stderr has no line matching: %s\n' \
    "${name}" "${pattern}"
  sed 's/^/      stderr: /' "${__BASHKIT_TEST_CASE_DIR}/stderr"
  return 0
}

# test::stderr_has_only(name pattern)
#
# Checks that every line the case test::case_run ran last wrote to stderr
# matches <pattern>. No output at all passes.
#
# Globals:
#   __BASHKIT_TEST_CASE_DIR, __BASHKIT_TEST_PASSED, __BASHKIT_TEST_FAILED
# Arguments:
#   $1   The check's name.
#   $2   An extended regular expression, matched against each line.
# Outputs:
#   One "ok" or "FAIL" line on stdout, and the stderr of a failure.
# Returns:
#   Always 0.
test::stderr_has_only() {
  local -r name="$1"
  local -r pattern="$2"

  if ! grep -qvE -- "${pattern}" "${__BASHKIT_TEST_CASE_DIR}/stderr"; then
    __BASHKIT_TEST_PASSED+=1
    printf 'ok    %s\n' "${name}"
    return 0
  fi

  __BASHKIT_TEST_FAILED+=1
  printf 'FAIL  %s\n      stderr has a line not matching: %s\n' \
    "${name}" "${pattern}"
  sed 's/^/      stderr: /' "${__BASHKIT_TEST_CASE_DIR}/stderr"
  return 0
}

# test::stderr_is_empty(name)
#
# Checks that the case test::case_run ran last wrote nothing to stderr.
#
# Globals:
#   __BASHKIT_TEST_CASE_DIR, __BASHKIT_TEST_PASSED, __BASHKIT_TEST_FAILED
# Arguments:
#   $1   The check's name.
# Outputs:
#   One "ok" or "FAIL" line on stdout, and the stderr of a failure.
# Returns:
#   Always 0.
test::stderr_is_empty() {
  local -r name="$1"

  if [[ ! -s "${__BASHKIT_TEST_CASE_DIR}/stderr" ]]; then
    __BASHKIT_TEST_PASSED+=1
    printf 'ok    %s\n' "${name}"
    return 0
  fi

  __BASHKIT_TEST_FAILED+=1
  printf 'FAIL  %s\n      stderr is not empty\n' "${name}"
  sed 's/^/      stderr: /' "${__BASHKIT_TEST_CASE_DIR}/stderr"
  return 0
}

# test::skip(name reason)
#
# Records a case that can't run here, and why.
#
# Globals:
#   __BASHKIT_TEST_SKIPPED
# Arguments:
#   $1   The case's name.
#   $2   Why it was skipped.
# Outputs:
#   One "skip" line on stdout.
# Returns:
#   Always 0.
test::skip() {
  __BASHKIT_TEST_SKIPPED+=1
  printf 'skip  %s (%s)\n' "$1" "$2"
  return 0
}

# test::summary_print()
#
# Prints the totals of the test file. Call it last: its status is the test
# file's status.
#
# Globals:
#   __BASHKIT_TEST_PASSED, __BASHKIT_TEST_FAILED, __BASHKIT_TEST_SKIPPED
# Arguments:
#   None.
# Outputs:
#   The totals on stdout.
# Returns:
#   0 when no check failed; 1 otherwise.
test::summary_print() {
  printf '\n%s: %d passed, %d failed, %d skipped\n' "${0##*/}" \
    "${__BASHKIT_TEST_PASSED}" "${__BASHKIT_TEST_FAILED}" \
    "${__BASHKIT_TEST_SKIPPED}"

  if (( __BASHKIT_TEST_FAILED > 0 )); then
    return 1
  fi
  return 0
}
