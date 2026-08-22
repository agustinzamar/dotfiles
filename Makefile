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
.PHONY: install test check lint bun-test build-tui

install:
	$(DOT) install

test:
	$(DOT) test

check:
	bash -n $(SCRIPTS)
	cd tools/tui && ./node_modules/.bin/tsc --noEmit

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SCRIPTS)

bun-test:
	cd tools/tui && bun test

# Self-contained installer binary; gitignored, built on demand here or by
# bin/dot's resolver when it is missing and Bun is available.
build-tui:
	cd $(DOTFILES_DIR)/tools/tui && bun install --frozen-lockfile \
		&& bun build --compile --minify src/main.ts --outfile $(DOTFILES_DIR)/bin/dot-tui
