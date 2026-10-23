.PHONY: test install uninstall

test:
	sh tests/run.sh

install:
	sudo sh install.sh

uninstall:
	sudo sh uninstall.sh
