.ONESHELL:
  SHELL := /bin/bash

install:
	mkdir -p ~/.local/bin
	install -v -t ~/.local/bin/ local/bin/*

	mkdir -p ~/.local/lib/bashkit
	install -v -t ~/.local/lib/bashkit local/lib/bashkit/*
