PROJECT_NAME := pac-build

DESTDIR :=
PREFIX := /usr
BINDIR := $(PREFIX)/bin
SYSCONFDIR := /etc
VARDIR := /var/pac
DATADIR := $(PREFIX)/share/$(PROJECT_NAME)

SCRIPTFILES = pac-build etc/pac-build.conf
DATAFILES   = library/*.sh

.PHONY: install install-program install-config clean
all: $(SCRIPTFILES)

pac-build: pac-build.in
	sed -e 's@^libdir=.*@libdir=$(DATADIR)@' \
	    -e '/^mydir=.*library$$/d' \
	        pac-build.in \
	      > pac-build

etc/pac-build.conf: etc/pac-build.conf.in
	sed -e 's@%%VARDIR%%@$(VARDIR)@g' $@.in > $@

install: install-program install-config

install-program:
	install -dm755                 "$(DESTDIR)$(BINDIR)"
	install -m755  pac-build      "$(DESTDIR)$(BINDIR)/pac-build"
	install -dm755                 "$(DESTDIR)$(DATADIR)"
	install -m644 $(DATAFILES)     "$(DESTDIR)$(DATADIR)/"
	install -dm755                 "$(DESTDIR)$(VARDIR)/scripts"
	install -m755 scripts/bashrc   "$(DESTDIR)$(VARDIR)/scripts/bashrc"
	install -m755 scripts/setup_root \
	                               "$(DESTDIR)$(VARDIR)/scripts/setup_root"
	install -m755 scripts/prepare_root \
	                               "$(DESTDIR)$(VARDIR)/scripts/prepare_root"

install-config:
	install -dm755                 "$(DESTDIR)$(SYSCONFDIR)"
	install -m644  etc/pac-build.conf \
	                               "$(DESTDIR)$(SYSCONFDIR)/pac-build.conf"

clean:
	rm $(SCRIPTFILES)
