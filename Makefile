#! /usr/bin/make -f

DEFAULTS = Makefile.config
CONFIG = Makefile.config

include $(DEFAULTS)
include $(CONFIG)

RELEASE          = $(shell cat RELEASE)
INSTALL_PLUGINS ?= "auto manual contrib snmpauto"
INSTALL          = ./install-sh
DIR              = $(shell /bin/pwd | sed 's/^.*\///')

default: build

install: install-main install-node install-node-plugins install-doc install-man

install-main: build
	$(CHECKUSER)
	mkdir -p $(CONFDIR)/templates
	mkdir -p $(LIBDIR)
	mkdir -p $(BINDIR)
	mkdir -p $(PERLLIB)

	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(HTMLDIR)
	mkdir -p $(DBDIR)
	mkdir -p $(CGIDIR)

	$(CHOWN) $(USER) $(LOGDIR) $(STATEDIR) $(RUNDIR) $(HTMLDIR) $(DBDIR)

	for p in build/server/*.tmpl; do    		              \
		$(INSTALL) -m 0644 "$$p" $(CONFDIR)/templates/ ; \
	done
	$(INSTALL) -m 0644 server/logo.png $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/style.css $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/definitions.html $(CONFDIR)/templates/
	$(INSTALL) -m 0644 server/VeraMono.ttf $(LIBDIR)/

	test -f "$(CONFDIR)/munin.conf"  || $(INSTALL) -m 0644 build/server/munin.conf $(CONFDIR)/

	$(INSTALL) -m 0755 build/server/munin-cron $(BINDIR)/

	$(INSTALL) -m 0755 build/server/munin-update $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-graph $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-html $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-limits $(LIBDIR)/
	$(INSTALL) -m 0755 build/server/munin-cgi-graph $(CGIDIR)/

	$(INSTALL) -m 0644 build/server/Munin.pm $(PERLLIB)/

install-node: build install-node-non-snmp install-node-snmp install-munindoc
	echo Done.

install-node-snmp: build
	$(INSTALL) -m 0755 build/node/munin-node-configure-snmp $(SBINDIR)/

install-munindoc: build 
	mkdir -p $(BINDIR)
	$(INSTALL) -m 0755 build/node/munindoc $(BINDIR)/ 
	
install-node-non-snmp: build
	$(CHECKGROUP)
	mkdir -p $(CONFDIR)/plugins
	mkdir -p $(CONFDIR)/plugin-conf.d
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(SBINDIR)
	mkdir -p $(PERLLIB)/Munin/Plugin

	mkdir -p $(LOGDIR)
	mkdir -p $(STATEDIR)
	mkdir -p $(PLUGSTATE)

	$(CHOWN) $(PLUGINUSER):$(GROUP) $(PLUGSTATE)
	$(CHMOD) 775 $(PLUGSTATE)
	$(CHMOD) 755 $(CONFDIR)/plugin-conf.d

	$(INSTALL) -m 0755 build/node/munin-node $(SBINDIR)/
	$(INSTALL) -m 0755 build/node/munin-node-configure $(SBINDIR)/
	test -f "$(CONFDIR)/munin-node.conf" || $(INSTALL) -m 0644 build/node/munin-node.conf $(CONFDIR)/
	$(INSTALL) -m 0755 build/node/munin-run $(SBINDIR)/

# ALWAYS DO THE OS SPECIFIC PLUGINS LAST! THAT WAY THEY OVERWRITE THE 
# GENERIC ONES 
install-node-plugins: build
	for p in build/node/node.d/* build/node/node.d.$(OSTYPE)/*; do    		\
		if test -f "$$p" ; then                                     		\
			family=`sed -n 's/^#%# family=\(.*\)$$/\1/p' $$p`;  		\
			test "$$family" || family=contrib;                  		\
			if echo $(INSTALL_PLUGINS) | grep $$family >/dev/null; then 	\
				$(INSTALL) -m 0755 $$p $(LIBDIR)/plugins/;    		\
			fi;                                                 		\
		fi                                                          		\
	done
	$(INSTALL) -m 0644 build/node/plugins.history $(LIBDIR)/plugins/
	$(INSTALL) -m 0644 build/node/plugin.sh $(LIBDIR)/plugins/
	mkdir -p $(PERLLIB)/Munin
	$(INSTALL) -m 0644 build/node/Plugin.pm $(PERLLIB)/Munin/

	#TODO:
	#configure plugins.

install-man: build-man
	mkdir -p $(MANDIR)/man1 $(MANDIR)/man5 $(MANDIR)/man8 $(MANDIR)/man1
	$(INSTALL) -m 0644 build/doc/munin-node.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin.conf.5 $(MANDIR)/man5/
	$(INSTALL) -m 0644 build/doc/munin-node.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-node-configure.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-node-configure-snmp.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-run.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-graph.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-update.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-limits.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-html.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munin-cron.8 $(MANDIR)/man8/
	$(INSTALL) -m 0644 build/doc/munindoc.1 $(MANDIR)/man1/

install-doc: build-doc
	mkdir -p $(DOCDIR)
	$(INSTALL) -m 0644 build/doc/munin-doc.html $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-doc.pdf $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-doc.txt $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.html $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.pdf $(DOCDIR)/
	$(INSTALL) -m 0644 build/doc/munin-faq.txt $(DOCDIR)/
	$(INSTALL) -m 0644 README.* $(DOCDIR)/
	$(INSTALL) -m 0644 COPYING $(DOCDIR)/
	$(INSTALL) -m 0644 build/README-apache-cgi $(DOCDIR)/
	$(INSTALL) -m 0644 node/node.d/README $(DOCDIR)/README.plugins

build: build-stamp

build-stamp:
	@for file in `find . -type f -name '*.in'`; do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating $$destname..;				\
		mkdir -p build/`dirname $$file`;			\
		sed -e 's|@@PREFIX@@|$(PREFIX)|g'			\
		    -e 's|@@CONFDIR@@|$(CONFDIR)|g'			\
		    -e 's|@@BINDIR@@|$(BINDIR)|g'			\
		    -e 's|@@SBINDIR@@|$(SBINDIR)|g'			\
		    -e 's|@@DOCDIR@@|$(DOCDIR)|g'			\
		    -e 's|@@LIBDIR@@|$(LIBDIR)|g'			\
		    -e 's|@@MANDIR@@|$(MANDIR)|g'			\
		    -e 's|@@LOGDIR@@|$(LOGDIR)|g'			\
		    -e 's|@@HTMLDIR@@|$(HTMLDIR)|g'			\
		    -e 's|@@DBDIR@@|$(DBDIR)|g'				\
		    -e 's|@@STATEDIR@@|$(STATEDIR)|g'			\
		    -e 's|@@PERL@@|$(PERL)|g'				\
		    -e 's|@@PERLLIB@@|$(PERLLIB)|g'			\
		    -e 's|@@PYTHON@@|$(PYTHON)|g'				\
		    -e 's|@@OSTYPE@@|$(OSTYPE)|g'				\
		    -e 's|@@HOSTNAME@@|$(HOSTNAME)|g'			\
		    -e 's|@@MKTEMP@@|$(MKTEMP)|g'			\
		    -e 's|@@VERSION@@|$(VERSION)|g'			\
		    -e 's|@@PLUGSTATE@@|$(PLUGSTATE)|g'			\
		    -e 's|@@CGIDIR@@|$(CGIDIR)|g'			\
		    -e 's|@@USER@@|$(USER)|g'				\
		    -e 's|@@GROUP@@|$(GROUP)|g'				\
		    -e 's|@@PLUGINUSER@@|$(PLUGINUSER)|g'		\
		    -e 's|@@GOODSH@@|$(GOODSH)|g'			\
		    -e 's|@@BASH@@|$(BASH)|g'				\
		    -e 's|@@HASSETR@@|$(HASSETR)|g'			\
		    $$file > build/$$destname;				\
	done
	touch build-stamp

build-doc: build-doc-stamp

build-doc-stamp:
	mkdir -p build/doc
	-htmldoc munin-doc-base.html > build/doc/munin-doc.html
	-htmldoc -t pdf --webpage build/doc/munin-doc.html > build/doc/munin-doc.pdf
	-html2text -style pretty -nobs build/doc/munin-doc.html > build/doc/munin-doc.txt

	-htmldoc munin-faq-base.html > build/doc/munin-faq.html
	-htmldoc -t pdf --webpage build/doc/munin-faq.html > build/doc/munin-faq.pdf
	-html2text -style pretty -nobs build/doc/munin-faq.html > build/doc/munin-faq.txt

	touch build-doc-stamp

build-man: build-man-stamp

build-man-stamp: build
	mkdir -p build/doc
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/node/munin-node > build/doc/munin-node.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/node/munin-run > build/doc/munin-run.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/node/munin-node-configure-snmp > build/doc/munin-node-configure-snmp.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/node/munin-node-configure > build/doc/munin-node-configure.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/server/munin-graph > build/doc/munin-graph.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/server/munin-update > build/doc/munin-update.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/server/munin-limits > build/doc/munin-limits.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		build/server/munin-html > build/doc/munin-html.8
	pod2man  --section=8 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin-cron.pod > build/doc/munin-cron.8
	pod2man  --section=5 --release=$(RELEASE) --center="Munin Documentation" \
		server/munin.conf.pod > build/doc/munin.conf.5
	pod2man  --section=5 --release=$(RELEASE) --center="Munin Documentation" \
		node/munin-node.conf.pod > build/doc/munin-node.conf.5
	pod2man  --section=1 --release=$(RELEASE) --center="Munin Documentation" \
		build/node/munindoc > build/doc/munindoc.1

	touch build-man-stamp

deb:
	-rm debian
	-ln -s dists/debian
	fakeroot debian/rules binary

rpm-pre:
	@for file in `find dists/redhat/ -type f -name '*.in'`; do			\
		destname=`echo $$file | sed 's/.in$$//'`;		\
		echo Generating $$destname..;				\
		sed -e 's|@@VERSION@@|$(VERSION)|g'			\
		    $$file > $$destname;				\
	done
	-cp dists/tarball/plugins.conf .
#	(cd ..; ln -s munin munin-$(VERSION))

rpm: rpm-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin-$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -tb munin-$(RELEASE).tar.gz)
	
rpm-src: rpm-pre
	tar -C .. --dereference --exclude .svn -cvzf ../munin-$(RELEASE).tar.gz munin-$(VERSION)/
	(cd ..; rpmbuild -ts munin-$(RELEASE).tar.gz)

+suse-pre:
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

clean:
ifeq ($(MAKELEVEL),0)
	-rm -f debian
	-ln -sf dists/debian
	-fakeroot debian/rules clean
	-rm -f debian
endif
	-rm -rf build
	-rm -f build-stamp
	-rm -f build-doc-stamp
	-rm -f build-man-stamp

	-rm -f dists/redhat/munin.spec

source_dist: clean
	(cd ..; ln -s $(DIR) munin-$(VERSION))
	tar -C .. --dereference --exclude .svn -cvzf ../munin_$(RELEASE).tar.gz munin-$(VERSION)/

node-monkeywrench: install-node
	rm -rf $(CONFDIR)/plugins
	rm -rf $(LIBDIR)/plugins
	mkdir -p $(LIBDIR)/plugins
	mkdir -p $(CONFDIR)/plugins
	cp monkeywrench/plugin-break*_ $(LIBDIR)/plugins/
	$(SBINDIR)/munin-node-configure --suggest
	echo 'Done?'

.PHONY: install install-main install-node install-doc install-man build build-doc deb clean source_dist