DOTFILES_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash
# Bare `make` shows usage; `make install` is the first-init entry point.
.DEFAULT_GOAL := help

# Call the CLI by path. Exporting PATH here does not work: make 3.81 (what
# macOS ships) execs single-word recipes itself, using the PATH it started
# with, so a bare `dot` is not found.
DOT := $(DOTFILES_DIR)/bin/dot

SCRIPTS := bin/dot install/*.sh system/defaults/*.sh remote-install.sh

# Everything else is `dot <command>` — this file only carries the first-init
# entry point and the lint targets CI runs.
# `install` and `test` are also directory names, so these must stay phony.
.PHONY: help install test check lint format bun-test build-tui

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  install       First-init entry point (runs dot install)"
	@echo "  test          Run the Bats test suite"
	@echo "  check         Syntax-check shell scripts and TypeScript"
	@echo "  lint          Check formatting (Prettier + shfmt + shellcheck)"
	@echo "  format        Auto-fix formatting"
	@echo "  bun-test      Run Bun tests for tools/tui"
	@echo "  build-tui     Build the installer TUI binary"

install:
	$(DOT) install

test:
	$(DOT) test

check:
	bash -n $(SCRIPTS)
	cd tools/tui && ./node_modules/.bin/tsc --noEmit

lint:
	cd tools/tui && bunx prettier --check src
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SCRIPTS)

# Canonical formatting for the repo: Prettier for TS/TSX (tools/tui/src) +
# shfmt for shell. `make lint`/CI enforce this; run `make format` to write it.
format:
	cd tools/tui && bunx prettier --write src
	shfmt -w $(SCRIPTS)

bun-test:
	cd tools/tui && bun test

# Self-contained installer binary; gitignored, built on demand here or by
# bin/dot's resolver when it is missing and Bun is available.
build-tui:
	cd $(DOTFILES_DIR)/tools/tui && bun install --frozen-lockfile \
		&& bun build --compile --minify src/main.ts --outfile $(DOTFILES_DIR)/bin/dot-tui
