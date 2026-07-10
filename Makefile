.PHONY: build install clean test

build:
	go build -o dotfiles .

install: build
	ln -sf $(PWD)/dotfiles /opt/homebrew/bin/dotfiles
	@echo "Installed to /opt/homebrew/bin/dotfiles"

clean:
	rm -f dotfiles
	rm -f /opt/homebrew/bin/dotfiles

test:
	go vet ./...
	go test ./...
