PROJECT_NAME := absd-build

PREFIX := /usr
BINDIR := $(PREFIX)/bin
SYSCONFDIR := /etc
VARDIR := /var/absd
DATADIR := $(PREFIX)/share/$(PROJECT_NAME)

all: absd-build

absd-build: absd-build.in
	sed -e 's@^libdir=.*@libdir=$(DATADIR)@' \
	    -e '/^mydir=.*library$$/d' \
	        absd-build.in \
	      > absd-build
