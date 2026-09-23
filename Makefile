.ONESHELL:
  SHELL := /bin/bash

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: help

# Every shell file: libs by extension, wrappers by location (no extension).
LINT_FILES := $(shell find local -type f \( -name '*.sh' -o -path 'local/bin/*' \) | sort)

lint: ## Lint all shell files with ShellCheck using .shellcheckrc (docs/STYLEGUIDE.md)
	shellcheck $(LINT_FILES)

.PHONY: lint

install: ## Install local/bin and local/lib/bashkit (recursively) into ~/.local
	mkdir -p ~/.local/bin
	install -v -t ~/.local/bin/ local/bin/*

	while IFS= read -r -d '' file; do
	  install -v -Dm644 "$${file}" "$${HOME}/.local/lib/bashkit/$${file#local/lib/bashkit/}"
	done < <(find local/lib/bashkit -type f -print0)
