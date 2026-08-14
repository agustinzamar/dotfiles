DOTFILES_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash
# A bare `make` is the first-init entry point: install.
.DEFAULT_GOAL := install

# Call the CLI by path. Exporting PATH here does not work: make 3.81 (what
# macOS ships) execs single-word recipes itself, using the PATH it started
# with, so a bare `dot` is not found.
DOT := $(DOTFILES_DIR)/bin/dot

SCRIPTS := bin/dot install/*.sh system/defaults/*.sh remote-install.sh

# Everything else is `dot <command>` — this file only carries the first-init
# entry point and the lint targets CI runs.
# `install` and `test` are also directory names, so these must stay phony.
.PHONY: install test check lint go-test

install:
	$(DOT) install

test:
	$(DOT) test

check:
	bash -n $(SCRIPTS)
	go vet ./...

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SCRIPTS)

go-test:
	go test ./...
