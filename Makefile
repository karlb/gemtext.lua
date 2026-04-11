PREFIX ?= $(HOME)/.local
WRITERDIR ?= $(PREFIX)/share/pandoc/custom-writers

.PHONY: test install uninstall

test:
	bash test/run-tests.sh

install:
	install -d $(DESTDIR)$(WRITERDIR)
	install -m 0644 gemtext.lua $(DESTDIR)$(WRITERDIR)/gemtext.lua

uninstall:
	rm -f $(DESTDIR)$(WRITERDIR)/gemtext.lua
