PROJECT_NAME := absd-build

DESTDIR :=
PREFIX := /usr
BINDIR := $(PREFIX)/bin
SYSCONFDIR := /etc
VARDIR := /var/absd
DATADIR := $(PREFIX)/share/$(PROJECT_NAME)

SCRIPTFILES = absd-build etc/archbsd-build.conf absd-arch
DATAFILES   = library/*.sh

all: $(SCRIPTFILES)

absd-build: absd-build.in
	sed -e 's@^libdir=.*@libdir=$(DATADIR)@' \
	    -e '/^mydir=.*library$$/d' \
	        absd-build.in \
	      > absd-build

etc/archbsd-build.conf: etc/archbsd-build.conf.in
	sed -e 's@%%VARDIR%%@$(VARDIR)@g' $*.in > $@

absd-arch: absd-arch.in
	cp $@.in $@

install:
	install -dm755                 "$(DESTDIR)$(BINDIR)"
	install -m755  absd-build      "$(DESTDIR)$(BINDIR)/absd-build"
	install -m755  absd-arch       "$(DESTDIR)$(BINDIR)/absd-arch"
	install -dm755                 "$(DESTDIR)$(SYSCONFDIR)"
	install -m644  etc/archbsd-build.conf \
	                               "$(DESTDIR)$(SYSCONFDIR)/archbsd-build.conf"
	install -dm755                 "$(DESTDIR)$(DATADIR)"
	install -m644 $(DATAFILES)     "$(DESTDIR)$(DATADIR)/"
	install -dm755                 "$(DESTDIR)$(VARDIR)/scripts"
	install -m755 scripts/bashrc   "$(DESTDIR)$(VARDIR)/scripts/bashrc"
	install -m755 scripts/setup_root \
	                               "$(DESTDIR)$(VARDIR)/scripts/setup_root"
	install -m755 scripts/prepare_root \
	                               "$(DESTDIR)$(VARDIR)/scripts/prepare_root"

clean:
	rm $(SCRIPTFILES)
