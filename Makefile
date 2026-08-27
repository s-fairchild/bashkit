.ONESHELL:
  SHELL := /bin/bash

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: help

install: ## Install local/bin and local/lib/bashkit into ~/.local (BROKEN: install -t doesn't recurse, network/ and virsh/ subdirs are skipped)
	mkdir -p ~/.local/bin
	install -v -t ~/.local/bin/ local/bin/*

	mkdir -p ~/.local/lib/bashkit
	install -v -t ~/.local/lib/bashkit local/lib/bashkit/*
