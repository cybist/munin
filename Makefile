# -*- makefile -*-
#
# Gnu make only.  Seriously.
#
# $Id$

# Defaults/paths. Allows $(CONFIG) to be overrided by
# make command line
DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

RELEASE          := $(shell cat RELEASE)
INSTALL_PLUGINS ?= "auto manual contrib snmpauto"
INSTALL          := ./install-sh
DIR              := $(shell /bin/pwd | sed 's/^.*\///')
INFILES          := $(shell find . -name '*.in' | sed 's/\.\/\(.*\)\.in$$/build\/\1/')
INFILES_MASTER   := $(shell find master -name '*.in' | sed 's/\(.*\)\.in$$/build\/\1/')
PLUGINS		 := $(wildcard plugins/node.d.$(OSTYPE)/* plugins/node.d/*)
MANCENTER        := "Munin Documentation"
MAN8		 := master/_bin/munin-graph master/_bin/munin-update \
			master/_bin/munin-limits master/_bin/munin-html \
			master/_bin/munin-gather
PODMAN8          := master/doc/munin-cron master/doc/munin master/doc/munin-check
PODMAN5          := master/doc/munin.conf node/doc/munin-node.conf

.PHONY: install install-pre install-master-prime install-node-prime install-node-pre install-common-prime install-munindoc install-doc install-man \
        build build-common-prime build-common-pre build-doc \
        deb source_dist \
        test clean \
        clean-% test-% build-% install-% \
	tags

.SECONDARY: node/Build master/Build plugins/Build

default: build

uninstall: 
	echo "Uninstall is not implemented yet"

# This removes the installed config so that the next install-pass installs
# a new config.  Target suitable for maintainers
unconfig:
	rm -f $(HTMLDIR)/.htaccess
	rm -f $(CONFDIR)/munin.conf

tags:
	-rm -f TAGS
	find master common -type f | egrep -v '/(build|_build|blib|.svn|t)/' | xargs etags -l perl -a

######################################################################

install: install-master-prime install-common-prime install-node-prime install-plugins-prime install-man install-munindoc

install-pre: Makefile Makefile.config
	@$(CHECKUSER)
	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(CONFDIR)
	$(CHOWN) $(USER) $(LOGDIR) $(STATEDIR)

install-master-prime: $(INFILES_MASTER) install-pre install-master
	mkdir -p $(CONFDIR)/templates
	mkdir -p $(LIBDIR)
	mkdir -p $(BINDIR)
	mkdir -p $(PERLLIB)
	mkdir -p $(PERLLIB)/Munin/Master
	mkdir -p $(HTMLDIR)
	mkdir -p $(DBDIR)
	mkdir -p $(CGIDIR)

	$(CHOWN) $(USER) $(HTMLDIR) $(DBDIR)

	for p in build/master/www/*.tmpl; do   		         \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/templates/ ; \
	done
	$(INSTALL) -m 0644 master/www/logo.png $(CONFDIR)/templates/
	$(INSTALL) -m 0644 master/www/style.css $(CONFDIR)/templates/
	$(INSTALL) -m 0644 master/www/definitions.html $(CONFDIR)/templates/
	$(INSTALL) -m 0755 master/VeraMono.ttf $(LIBDIR)/
	$(INSTALL) -m 0644 resources/favicon.ico $(HTMLDIR)/

	test -f $(HTMLDIR)/.htaccess || $(INSTALL) -m 0644 build/master/www/munin-htaccess $(HTMLDIR)/.htaccess
	test -f "$(CONFDIR)/munin.conf"  || $(INSTALL) -m 0644 build/master/munin.conf $(CONFDIR)/

	$(INSTALL) -m 0755 build/master/_bin/munin-cron $(BINDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-check $(BINDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-html $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-limits $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-gather $(LIBDIR)/
	$(INSTALL) -m 0755 build/master/_bin/munin-cgi-graph $(CGIDIR)/


# ALWAYS DO THE OS SPECIFIC PLUGINS LAST! THAT WAY THEY OVERWRITE THE
# GENERIC ONES

install-node-plugins: install-plugins-prime

# Some HP-UX plugins needs *.adv support files in LIBDIR
install-plugins-prime: install-plugins build $(PLUGINS) Makefile Makefile.config
	@$(CHECKGROUP)

	mkdir -p $(CONFDIR)/plugins
	mkdir -p $(CONFDIR)/plugin-conf.d
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(PLUGSTATE)

	$(CHOWN) $(PLUGINUSER):$(GROUP) $(PLUGSTATE)
	$(CHMOD) 0775 $(PLUGSTATE)
	$(CHMOD) 0755 $(CONFDIR)/plugin-conf.d

	for p in build/plugins/node.d/* build/plugins/node.d.$(OSTYPE)/* ; do \
	    if test -f "$$p" ; then                                    \
		family=`sed -n 's/^[[:space:]]*#%# family=\(.*\)$$/\1/p' $$p`;\
		test "$$family" || family=contrib;                     \
		if echo $(INSTALL_PLUGINS) |                           \
		   grep $$family >/dev/null; then 	               \
			echo Installing $$p;                           \
			$(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/;     \
		fi;                                                    \
	    fi                                                         \
	done
	-mv $(LIBDIR)/plugins/*.adv $(LIBDIR)
	$(INSTALL) -m 0644 build/plugins/plugins.history $(LIBDIR)/plugins/
	$(INSTALL) -m 0644 build/plugins/plugin.sh $(LIBDIR)/plugins/

#TODO:
# configure plugins.  Or not. Better done under the direction of the installer
# or the packager.

install-node-prime: install-node-pre install-node

install-node-pre: build/node/munin-node.conf install-pre
	test -f "$(CONFDIR)/munin-node.conf" || $(INSTALL) -m 0644 build/node/munin-node.conf $(CONFDIR)/


install-common-prime: build-common install-common


install-man: build-man Makefile Makefile.config
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8
	$(INSTALL) -m 0644 build/doc/munin-node.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-limits.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-cron.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-check.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin.8 $(MANDIR)/man8/


install-doc: build-doc
	mkdir -p $(DOCDIR)/resources
	$(INSTALL) -m 0644 README $(DOCDIR)/
	$(INSTALL) -m 0644 COPYING $(DOCDIR)/
	$(INSTALL) -m 0644 build/resources/* $(DOCDIR)/resources

install-munindoc: build
	mkdir -p $(BINDIR)
	$(INSTALL) -m 0755 build/node/bin/munindoc $(BINDIR)/


######################################################################

build: $(INFILES) build-master build-common-prime build-node build-plugins build-man

build/%: %.in
	@echo "$< -> $@"
	@mkdir -p build/`dirname $<`
	@sed -e 's|@@PREFIX@@|$(PREFIX)|g'                      \
             -e 's|@@CONFDIR@@|$(CONFDIR)|g'                    \
             -e 's|@@BINDIR@@|$(BINDIR)|g'                      \
             -e 's|@@SBINDIR@@|$(SBINDIR)|g'                    \
             -e 's|@@DOCDIR@@|$(DOCDIR)|g'                      \
             -e 's|@@LIBDIR@@|$(LIBDIR)|g'                      \
             -e 's|@@MANDIR@@|$(MANDIR)|g'                      \
             -e 's|@@LOGDIR@@|$(LOGDIR)|g'                      \
             -e 's|@@HTMLDIR@@|$(HTMLDIR)|g'                    \
             -e 's|@@DBDIR@@|$(DBDIR)|g'                        \
             -e 's|@@STATEDIR@@|$(STATEDIR)|g'                  \
             -e 's|@@PERL@@|$(PERL)|g'                          \
             -e 's|@@PERLLIB@@|$(PERLLIB)|g'                    \
             -e 's|@@PYTHON@@|$(PYTHON)|g'                      \
             -e 's|@@RUBY@@|$(RUBY)|g'                          \
             -e 's|@@OSTYPE@@|$(OSTYPE)|g'                      \
             -e 's|@@HOSTNAME@@|$(HOSTNAME)|g'                  \
             -e 's|@@MKTEMP@@|$(MKTEMP)|g'                      \
             -e 's|@@VERSION@@|$(VERSION)|g'                    \
             -e 's|@@PLUGSTATE@@|$(PLUGSTATE)|g'                \
             -e 's|@@CGIDIR@@|$(CGIDIR)|g'                      \
             -e 's|@@USER@@|$(USER)|g'                          \
             -e 's|@@GROUP@@|$(GROUP)|g'                        \
             -e 's|@@PLUGINUSER@@|$(PLUGINUSER)|g'              \
             -e 's|@@GOODSH@@|$(GOODSH)|g'                      \
             -e 's|@@BASH@@|$(BASH)|g'                          \
             -e 's|@@HASSETR@@|$(HASSETR)|g'                    \
             -e 's|@@SSPOOLDIR@@|$(SSPOOLDIR)|g'                \
             $< > $@;


build-common-prime: build-common-pre common/blib/lib/Munin/Common/Defaults.pm build-common

build-common-pre: common/Build
	cd common && $(PERL) Build code
	rm -f common/blib/lib/Munin/Common/Defaults.pm

common/blib/lib/Munin/Common/Defaults.pm: common/lib/Munin/Common/Defaults.pm
	$(PERL) -pe 's{(PREFIX     \s+=\s).*}{\1q{$(PREFIX)};}x;   \
                  s{(CONFDIR    \s+=\s).*}{\1q{$(CONFDIR)};}x;     \
                  s{(BINDIR     \s+=\s).*}{\1q{$(BINDIR)};}x;      \
                  s{(SBINDIR    \s+=\s).*}{\1q{$(SBINDIR)};}x;     \
                  s{(DOCDIR     \s+=\s).*}{\1q{$(DOCDIR)};}x;      \
                  s{(LIBDIR	\s+=\s).*}{\1q{$(LIBDIR)};}x;      \
                  s{(MANDIR	\s+=\s).*}{\1q{$(MANDIR)};}x;      \
                  s{(LOGDIR	\s+=\s).*}{\1q{$(LOGDIR)};}x;      \
                  s{(HTMLDIR	\s+=\s).*}{\1q{$(HTMLDIR)};}x;     \
                  s{(DBDIR	\s+=\s).*}{\1q{$(DBDIR)};}x;       \
                  s{(STATEDIR	\s+=\s).*}{\1q{$(STATEDIR)};}x;    \
                  s{(PERL	\s+=\s).*}{\1q{$(PERL)};}x;        \
                  s{(PERLLIB	\s+=\s).*}{\1q{$(PERLLIB)};}x;     \
                  s{(PYTHON	\s+=\s).*}{\1q{$(PYTHON)};}x;      \
                  s{(RUBY       \s+=\s).*}{\1q{$(RUBY)};}x;        \
                  s{(OSTYPE	\s+=\s).*}{\1q{$(OSTYPE)};}x;      \
                  s{(HOSTNAME	\s+=\s).*}{\1q{$(HOSTNAME)};}x;    \
                  s{(MKTEMP	\s+=\s).*}{\1q{$(MKTEMP)};}x;      \
                  s{(VERSION	\s+=\s).*}{\1q{$(VERSION)};}x;     \
                  s{(PLUGSTATE	\s+=\s).*}{\1q{$(PLUGSTATE)};}x;   \
                  s{(CGIDIR	\s+=\s).*}{\1q{$(CGIDIR)};}x;      \
                  s{(USER	\s+=\s).*}{\1q{$(USER)};}x;        \
                  s{(GROUP	\s+=\s).*}{\1q{$(GROUP)};}x;       \
                  s{(PLUGINUSER	\s+=\s).*}{\1q{$(PLUGINUSER)};}x;  \
                  s{(GOODSH	\s+=\s).*}{\1q{$(GOODSH)};}x;      \
                  s{(BASH	\s+=\s).*}{\1q{$(BASH)};}x;        \
                  s{(HASSETR	\s+=\s).*}{\1q{$(HASSETR)};}x;     \
	          s{(SSPOOLDIR	\s+=\s).*}{\1q{$(SSPOOLDIR)};}x;'  \
                  $< > $@

build-doc: build-doc-stamp Makefile Makefile.config

build-doc-stamp:
	touch build-doc-stamp
	mkdir -p build/doc

build-man: build-man-stamp 

build-man-stamp: build Makefile Makefile.config
	touch build-man-stamp
	mkdir -p build/doc
	for f in $(MAN8); do \
	   pod2man --section=8 --release=$(RELEASE) --center=$(MANCENTER) build/"$$f" > build/doc/`basename $$f`.8; \
	done
	for f in $(PODMAN8); do \
	   pod2man --section=8 --release=$(RELEASE) --center=$(MANCENTER) "$$f".pod > build/doc/`basename $$f .pod`.8; \
	done
	for f in $(PODMAN5); do \
	   pod2man --section=5 --release=$(RELEASE) --center=$(MANCENTER) "$$f".pod > build/doc/`basename $$f .pod`.5; \
	done

######################################################################
# DIST RULES

deb:
	(! grep MAINTAINER Makefile.config)
	-rm debian
	-ln -s dists/debian
	fakeroot debian/rules binary

tar-pre:
	(! grep MAINTAINER Makefile.config)
	find . -name '*~' -exec rm -fv {} \;
	PWD=`pwd`
	-rm -f ../munin-$(VERSION)
	(cd ..; ln -s $(PWD) munin-$(VERSION))

tar: tar-pre
	GZIP=-9 tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/

rpm-pre:
	(! grep MAINTAINER Makefile.config)
	@for file in `find dists/redhat/ -type f -name '*.in'`; do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating $$destname..;				\
		sed -e 's|@@VERSION@@|$(VERSION)|g'			\
		    $$file > $$destname;				\
	done
	-cp dists/tarball/plugins.conf .
#	(cd ..; ln -s munin munin-$(VERSION))

rpm: rpm-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -tb munin_$(RELEASE).tar.gz)

rpm-src: rpm-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin-$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -ts munin-$(RELEASE).tar.gz)

suse-pre:
	(! grep MAINTAINER Makefile.config)
	@for file in `find dists/suse/ -type f -name '*.in'`; do                \
		destname=`echo $$file | sed 's/.in$$//'`;               \
		echo Generating $$destname..;                           \
		sed -e 's|@@VERSION@@|$(VERSION)|g'                     \
		$$file > $$destname;                                \
	done
	-cp dists/tarball/plugins.conf .
#	(cd ..; ln -s munin munin-$(VERSION))

suse: suse-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -tb munin-$(RELEASE).tar.gz)

suse-src: suse-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -ts munin-$(RELEASE).tar.gz)

source_dist: clean
	(! grep MAINTAINER Makefile.config)
	(cd .. && ln -s $(DIR) munin-$(VERSION))
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/
	(cd .. && rm munin-$(VERSION))

######################################################################

ifeq ($(MAKELEVEL),0)
clean: clean-node clean-master clean-plugins clean-common
	-rm -f debian
	-ln -sf dists/debian
	-fakeroot debian/rules clean
	-rm -f debian
else
clean:
endif
	-rm -rf build
	-rm -f build-stamp
	-rm -f build-doc-stamp
	-rm -f build-man-stamp
	-rm -rf t/install

	-rm -f dists/redhat/munin.spec
	-rm -f dists/suse/munin.spec


######################################################################

test: test-common test-master test-node test-plugins

ifeq ($(MAKELEVEL),0)
# Re-exec make with the test config
old-test: t/*.t
	$(MAKE) $@ CONFIG=t/Makefile.config
else
test_plugins = id_default id_root env
old-test: t/*.t t/install $(addprefix $(CONFDIR)/plugins/,$(test_plugins))
	@for test in t/*.t; do \
		echo -n "$$test: "; \
		PERL5LIB=$(PERLLIB) $(PERL) $$test;\
	done
endif

node-monkeywrench: install-node
	rm -rf $(CONFDIR)/plugins
	rm -rf $(LIBDIR)/plugins
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(CONFDIR)/plugins
	cp monkeywrench/plugin-break*_ $(LIBDIR)/plugins/
	$(SBINDIR)/munin-node-configure --suggest
	echo 'Done?'

t/install: 
	$(MAKE) clean install-node-prime install-node-plugins CONFIG=t/Makefile.config INSTALL_PLUGINS=test


######################################################################

# This builds */Build from Build.PL
%/Build: %/Build.PL
	cd $* && $(PERL) Build.PL

build-%: %/Build
	cd $* && $(PERL) Build

# BUG: the Build script writes files under PWD when it does "install"
# can't seem to find a way to persuade it to write otherwhere.
install-%: %/Build
	cd $* && $(PERL) Build install			\
            --install_path lib=$(PERLLIB)		\
            --install_path bin=$(BINDIR)		\
            --install_path script=$(BINDIR)		\
            --install_path sbin=$(SBINDIR)		\
            --install_path bindoc=$(MANDIR)/man1	\
            --install_path libdoc=$(MANDIR)/man3	\

test-%: %/Build
	cd $* && $(PERL) Build test || true

clean-%: %/Build
	cd $* && $(PERL) Build realclean
