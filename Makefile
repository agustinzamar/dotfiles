.PHONY: build install clean test ensure-go
.DEFAULT_GOAL := build

ensure-go:
	@command -v go >/dev/null 2>&1 || { \
		command -v brew >/dev/null 2>&1 || { \
			/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
			eval "$$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"; \
		}; \
		brew install go; \
	}

build: ensure-go
	go build -o dotfiles .

install: build
	ln -sf $(PWD)/dotfiles /opt/homebrew/bin/dotfiles
	@echo "Installed to /opt/homebrew/bin/dotfiles"

clean:
	rm -f dotfiles
	rm -f /opt/homebrew/bin/dotfiles

test: ensure-go
	go vet ./...
	go test ./...
