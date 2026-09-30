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
.PHONY: help install test check lint format

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  install       First-init entry point (runs dot install)"
	@echo "  test          Run the Bats test suite"
	@echo "  check         Syntax-check shell scripts"
	@echo "  lint          Check formatting (shfmt + shellcheck)"
	@echo "  format        Auto-fix formatting"

install:
	$(DOT) install

test:
	bats test/*.bats

check:
	bash -n $(SCRIPTS)

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SCRIPTS)

# Canonical formatting for the repo: shfmt for shell.
# `make lint`/CI enforce this; run `make format` to write it.
format:
	shfmt -w $(SCRIPTS)
