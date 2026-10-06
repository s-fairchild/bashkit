#!/bin/bash
#
# Behavior tests for the log file that local/lib/bashkit/core/logger-utils.sh
# chooses from BASHKIT_LOG_FILE, BASHKIT_LOG_DIR and BASHKIT_ENV. Run this
# file directly, or every test file with `make test`.

# shellcheck source=../test-utils.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../test-utils.sh"
test::suite_init || exit

###################################
### core::_logger_log_file_path ###
###################################

test::case_run 'log file: none unless a variable asks for one' 0 '[]' <<'CASE'
unset -v BASHKIT_LOG_FILE BASHKIT_LOG_DIR
. "${TEST_LIB}/core/logger-utils.sh"
echo "[$(core::_logger_log_file_path)]"
CASE

test::case_run 'log file: the environment'"'"'s file in BASHKIT_LOG_DIR' 0 \
  '/var/log/app/ci.log' <<'CASE'
unset -v BASHKIT_LOG_FILE
export BASHKIT_LOG_DIR=/var/log/app BASHKIT_ENV=ci
. "${TEST_LIB}/core/logger-utils.sh"
core::_logger_log_file_path
CASE

test::case_run 'log file: a trailing slash on BASHKIT_LOG_DIR' 0 \
  '/var/log/app/ci.log' <<'CASE'
unset -v BASHKIT_LOG_FILE
export BASHKIT_LOG_DIR=/var/log/app/ BASHKIT_ENV=ci
. "${TEST_LIB}/core/logger-utils.sh"
core::_logger_log_file_path
CASE

test::case_run 'log file: bashkit.log when BASHKIT_ENV is not set' 0 \
  '/var/log/app/bashkit.log' <<'CASE'
unset -v BASHKIT_LOG_FILE BASHKIT_ENV
export BASHKIT_LOG_DIR=/var/log/app
. "${TEST_LIB}/core/logger-utils.sh"
core::_logger_log_file_path
CASE

test::case_run 'log file: BASHKIT_LOG_FILE wins over BASHKIT_LOG_DIR' 0 \
  '/elsewhere/mine.log' <<'CASE'
export BASHKIT_LOG_FILE=/elsewhere/mine.log BASHKIT_LOG_DIR=/var/log/app
. "${TEST_LIB}/core/logger-utils.sh"
core::_logger_log_file_path
CASE

test::case_run 'log file: a BASHKIT_ENV that is not a name is rejected' 0 \
  'status=1 out=[]' <<'CASE'
unset -v BASHKIT_LOG_FILE
export BASHKIT_LOG_DIR=/var/log/app BASHKIT_ENV=../../etc/passwd
. "${TEST_LIB}/core/logger-utils.sh"
status=0
out="$(core::_logger_log_file_path)" || status=$?
echo "status=${status} out=[${out}]"
CASE
test::stderr_has 'log file: and reported' \
  'core::_logger_log_file_path\(\): BASHKIT_ENV is not a valid environment name'

test::case_run 'environment name: what is accepted' 0 \
  'dev=yes test-1=yes a.b=yes _x=yes =no .hidden=no -dash=no a/b=no a..b=no a b=no' \
  <<'CASE'
. "${TEST_LIB}/core/logger-utils.sh"
results=()
for name in dev test-1 a.b _x '' .hidden -dash a/b a..b 'a b'; do
  if core::_logger_env_is_valid "${name}"; then
    results+=("${name}=yes")
  else
    results+=("${name}=no")
  fi
done
echo "${results[*]}"
CASE

#########################
### core::logger_init ###
#########################

if [[ -f "${TEST_REPO}/vendor/bash-logger/logging.sh" ]]; then
  # What .envrc can't do with a file name of its own: one exported directory,
  # and a script that is started with another BASHKIT_ENV.
  test::case_run 'logger_init: each BASHKIT_ENV logs to its own file' 0 \
    "$(printf '%s\n' 'ci.log test.log' '1' '1')" <<'CASE'
unset -v BASHKIT_LOG_FILE
export BASHKIT_LOG_DIR="${PWD}/logs"
cat > run.sh <<'SCRIPT'
. "${TEST_LIB}/core/logger-utils.sh"
core::logger_init
log_info "hello from ${BASHKIT_ENV}"
SCRIPT
BASHKIT_ENV=test bash run.sh 2> /dev/null
BASHKIT_ENV=ci bash run.sh 2> /dev/null
ls logs | xargs
grep -c 'hello from test' logs/test.log
grep -c 'hello from ci' logs/ci.log
CASE

  test::case_run 'logger_init: BASHKIT_LOG_FILE is used instead of the directory' \
    0 'mine.log run.sh' <<'CASE'
export BASHKIT_LOG_FILE="${PWD}/mine.log" BASHKIT_LOG_DIR="${PWD}/logs"
cat > run.sh <<'SCRIPT'
. "${TEST_LIB}/core/logger-utils.sh"
core::logger_init
log_info "hello"
SCRIPT
bash run.sh 2> /dev/null
ls | xargs
CASE

  test::case_run 'logger_init: no log file with neither variable set' 0 \
    'run.sh' <<'CASE'
unset -v BASHKIT_LOG_FILE BASHKIT_LOG_DIR
cat > run.sh <<'SCRIPT'
. "${TEST_LIB}/core/logger-utils.sh"
core::logger_init
log_info "hello"
SCRIPT
bash run.sh 2> /dev/null
ls | xargs
CASE

  test::case_run 'logger_init: through import, the same file is chosen' 0 \
    'test.log' <<'CASE'
unset -v BASHKIT_LOG_FILE
export BASHKIT_LOG_DIR="${PWD}/logs"
cat > run.sh <<'SCRIPT'
. "${TEST_BOOTSTRAP}"
import core/contract-utils
log_info "hello"
SCRIPT
bash run.sh 2> /dev/null
ls logs | xargs
CASE
else
  test::skip 'logger_init: the log file bash-logger writes' \
    'vendor/bash-logger is not checked out'
fi

test::summary_print
