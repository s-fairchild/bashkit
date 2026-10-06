#!/bin/bash
#
# Behavior tests for local/lib/bashkit/array/contains.sh. Run this file
# directly, or every test file with `make test`.

# shellcheck source=../test-utils.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../test-utils.sh"
test::suite_init || exit

test::case_run 'contains: found' 0 'yes' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
array::contains b a b c && echo yes
CASE

test::case_run 'contains: not found returns 1' 0 'status=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
status=0
array::contains z a b c || status=$?
echo "status=${status}"
CASE
test::stderr_is_empty 'contains: not found prints nothing'

test::case_run 'contains: an empty list holds nothing' 0 'status=1' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
status=0
array::contains z || status=$?
echo "status=${status}"
CASE

test::case_run 'contains: an expanded array' 0 'yes no' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
names=("first item" second)
array::contains "first item" "${names[@]}" && printf 'yes '
array::contains first "${names[@]}" || echo no
CASE

test::case_run 'contains: glob characters compare literally' 0 'no yes' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
array::contains 'a*' abc || printf 'no '
array::contains 'a*' 'a*' && echo yes
CASE

test::case_run 'contains: an empty element can be looked for' 0 'yes no' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
array::contains '' a '' && printf 'yes '
array::contains '' a b || echo no
CASE

test::case_run "contains: leaves the caller's variables alone" 0 \
  'e=keep item=keep element=keep' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
e=keep
item=keep
element=keep
array::contains z a b || true
echo "e=${e} item=${item} element=${element}"
CASE

test::case_run 'contains: a missing element returns 2' 0 'status=2' <<'CASE'
. "${TEST_BOOTSTRAP}"
import array/contains
status=0
array::contains || status=$?
echo "status=${status}"
CASE
test::stderr_has 'contains: a missing element is reported' \
  '^array::contains\(\) - Exception: element=[$]1 is required\.$'

test::summary_print
