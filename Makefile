.ONESHELL:
  SHELL := /bin/bash

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: help

install: ## Install local/bin and local/lib/bashkit (recursively) into ~/.local
	mkdir -p ~/.local/bin
	install -v -t ~/.local/bin/ local/bin/*

	while IFS= read -r -d '' file; do
	  install -v -Dm644 "$${file}" "$${HOME}/.local/lib/bashkit/$${file#local/lib/bashkit/}"
	done < <(find local/lib/bashkit -type f -print0)
