PREFIX ?= $(HOME)/.local
BINDIR = $(DESTDIR)$(PREFIX)/bin
LIBDIR = $(DESTDIR)$(PREFIX)/lib/rofi-screens
APPDIR = $(DESTDIR)$(PREFIX)/share/applications

LIBS = $(wildcard lib/*.sh)

.PHONY: install uninstall link check desktop

install: desktop
	install -Dm755 rofi-screens $(BINDIR)/rofi-screens
	install -Dm644 -t $(LIBDIR) $(LIBS)

uninstall:
	rm -f $(BINDIR)/rofi-screens
	rm -rf $(LIBDIR)
	rm -f $(APPDIR)/rofi-screens*.desktop

# Symlink the working tree for development. The script resolves its own
# symlink and finds lib/ next to it, so nothing under $(LIBDIR) is needed.
link: desktop
	rm -rf $(LIBDIR)
	mkdir -p $(BINDIR)
	ln -sfn $(CURDIR)/rofi-screens $(BINDIR)/rofi-screens

# Launcher entries for the top menu and each backend, so a drun launcher
# finds them by name or by typing "screens". Rerun after adding a backend.
desktop:
	install -d $(APPDIR)
	rm -f $(APPDIR)/rofi-screens*.desktop
	@entry() { \
		printf '%s\n' '[Desktop Entry]' 'Type=Application' "Name=$$2" \
			'GenericName=Display Menu' "Exec=$(PREFIX)/bin/rofi-screens$$3" \
			"Icon=$$4" "Keywords=screens;display;monitor;$$5" \
			'Categories=Settings;HardwareSettings;' >"$$1"; \
		echo "wrote $$1"; \
	}; \
	entry $(APPDIR)/rofi-screens.desktop 'Screens' '' \
		preferences-desktop-display ''; \
	./rofi-screens --list | while IFS="$$(printf '\t')" read -r name label icon; do \
		entry "$(APPDIR)/rofi-screens-$$name.desktop" "$$label" " $$name" \
			"$$icon" "$$name;"; \
	done

check:
	shellcheck -x rofi-screens $(LIBS)
