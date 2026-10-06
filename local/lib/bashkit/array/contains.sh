# shellcheck shell=bash
#
# Array membership test. Load it with `import array/contains`: it reports a
# missing operand with os::throw, so os/bk-bootstrap.sh has to be sourced
# first.
#
# Based on: https://github.com/niieani/bash-oo-framework/blob/35fb3befff342c671fe31019cecbf3ad9d0ba81f/lib/Array/Contains.sh
# * Reference: https://github.com/niieani/bash-oo-framework/tree/master

# array::contains(element [item...])
#
# Tests whether <element> is one of the <item> operands. The comparison is a
# literal string match, so glob characters in either side are not special:
#
#   array::contains "${name}" "${names[@]}" && echo "known"
#
# Globals:
#   None.
# Arguments:
#   $1   The element to look for. May be an empty string.
#   $@   Optional. The items to search, usually an expanded array.
# Outputs:
#   Nothing, unless <element> is missing: then an error and stack trace.
# Returns:
#   0 if <element> equals one of the items; 1 if it doesn't; 2 if <element>
#   was not given.
array::contains() {
  (( $# > 0 )) || { r=2 os::throw "element=\$1 is required." || return; }
  local -r element="$1"

  local item
  for item in "${@:2}"; do
    [[ "${item}" == "${element}" ]] && return 0
  done

  # TODO add test for empty $@, print error message specifically for this if so.
  return 1
}
