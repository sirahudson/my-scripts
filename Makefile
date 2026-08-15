PREFIX ?= /usr/local

install:
	mkdir -p $(PREFIX)/bin
	install -m 755 docker/cmd-prune.sh $(PREFIX)/bin/cmd-prune
	install -m 755 docker/cmd_stats.sh $(PREFIX)/bin/cmd_stats

uninstall:
	rm -f $(PREFIX)/bin/cmd-prune
	rm -f $(PREFIX)/bin/cmd_stats
