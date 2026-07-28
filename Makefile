DOTFILES_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash

# Call the CLI by path. Exporting PATH here does not work: make 3.81 (what
# macOS ships) execs single-word recipes itself, using the PATH it started
# with, so a bare `dot` is not found.
DOT := $(DOTFILES_DIR)/bin/dot

SCRIPTS := bin/dot bin/is-* lib/*.sh install/*.sh macos/*.sh install.sh

# `install` and `test` are also directory names, so these must stay phony.
.PHONY: install link unlink update doctor backup test check lint

install:
	$(DOT) install

link:
	$(DOT) link

unlink:
	$(DOT) unlink

update:
	$(DOT) update

doctor:
	$(DOT) doctor

backup:
	$(DOT) backup

test:
	$(DOT) test

check:
	bash -n $(SCRIPTS)

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SCRIPTS)
