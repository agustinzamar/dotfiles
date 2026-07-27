DOTFILES_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash

# `export` rather than `SHELL := env PATH=...` so that a PATH containing
# spaces (Homebrew casks under ~/Library/Application Support) survives.
export PATH := $(DOTFILES_DIR)/bin:$(PATH)

SCRIPTS := bin/dot bin/is-* lib/*.sh install/*.sh macos/*.sh install.sh

# `install` and `test` are also directory names, so these must stay phony.
.PHONY: install link unlink update doctor backup test check lint

install:
	dot install

link:
	dot link

unlink:
	dot unlink

update:
	dot update

doctor:
	dot doctor

backup:
	dot backup

test:
	dot test

check:
	bash -n $(SCRIPTS)

lint:
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SCRIPTS)
