.PHONY: build install test lint

build:
	bash scripts/build-macos.sh

install: build
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/ChatBar.app"
	cp -R dist/ChatBar.app "$(HOME)/Applications/ChatBar.app"

test:
	bash tests/run.sh

lint:
	bash scripts/lint-iron-rule.sh
