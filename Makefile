PREFIX ?= /usr/local

install:
	mkdir -p $(PREFIX)/bin
	install -m 755 docker/cmd-prune.sh $(PREFIX)/bin/cmd-prune
	install -m 755 docker/cmd-stats.sh $(PREFIX)/bin/cmd-stats
	install -m 755 docker/cmd-logs.sh $(PREFIX)/bin/cmd-logs
	install -m 755 docker/cmd-shell.sh $(PREFIX)/bin/cmd-shell
	install -m 755 docker/cmd-run.sh $(PREFIX)/bin/cmd-run


uninstall:
	rm -f $(PREFIX)/bin/cmd-prune
	rm -f $(PREFIX)/bin/cmd-stats
	rm -f $(PREFIX)/bin/cmd-logs
	rm -f $(PREFIX)/bin/cmd-shell
	rm -f $(PREFIX)/bin/cmd-run
