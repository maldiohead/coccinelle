#############################################################################
# Configuration section
#############################################################################

include Makefile.libs

# 'distclean' does not require configure to have run, and should also
# clean all the bundled directories. Hence, a special case.
ifeq ($(MAKECMDGOALS),distclean)
MAKELIBS:=$(dir $(wildcard ./bundles/*/Makefile))
else
ifneq ($(MAKECMDGOALS),configure)
-include Makefile.config
endif
endif

-include /etc/lsb-release
-include Makefile.override         # local customizations, if any
-include /etc/Makefile.coccinelle  # local customizations, if any


VERSION=$(shell cat ./version | tr -d '\n')
CCVERSION=$(shell cat scripts/coccicheck/README | egrep -o '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+' | head -n1)
PKGVERSION=$(shell dpkg-parsechangelog -ldebian/changelog.$(DISTRIB_CODENAME) 2> /dev/null \
	 | sed -n 's/^Version: \(.*\)/\1/p' )

##############################################################################
# Variables
##############################################################################

TARGET=spatch
PRJNAME=coccinelle
SRC=flag_cocci.ml cocci.ml testing.ml test.ml $(LEXER_SOURCES:.mll=.ml) main.ml

ifeq ($(FEATURE_PYTHON),1)
	PYTHON_INSTALL_TARGET=install-python
else
	PYTHON_INSTALL_TARGET=
endif

SYSLIBS=str.cma unix.cma bigarray.cma nums.cma
LIBS=commons/commons.cma \
     commons/commons_sexp.cma \
     globals/globals.cma \
     ctl/ctl.cma \
     parsing_cocci/cocci_parser.cma parsing_c/parsing_c.cma \
     engine/cocciengine.cma popl09/popl.cma \
     extra/extra.cma python/coccipython.cma ocaml/cocciocaml.cma

MAKESUBDIRS=$(MAKELIBS) commons \
 globals ctl parsing_cocci parsing_c \
 engine popl09 extra python ocaml

CLEANSUBDIRS=commons \
 globals ctl parsing_cocci parsing_c \
 engine popl09 extra python ocaml docs \
 $(MAKELIBS)

INCLUDEDIRSDEP=commons commons/ocamlextra \
 globals ctl \
 parsing_cocci parsing_c engine popl09 extra python ocaml \
 $(MAKELIBS)

INCLUDEDIRS=$(INCLUDEDIRSDEP) $(PCREDIR) $(INCLIBS)

##############################################################################
# Generic variables
##############################################################################

# sort to remove duplicates
INCLUDESET=$(sort $(INCLUDEDIRS))
INCLUDES=$(INCLUDESET:%=-I %)

OBJS=    $(SRC:.ml=.cmo)
OPTOBJS= $(SRC:.ml=.cmx)

EXEC=$(TARGET)

##############################################################################
# Generic ocaml variables
##############################################################################

OCAMLC_CMD=$(OCAMLC) $(OCAMLCFLAGS) $(INCLUDES)
OCAMLOPT_CMD=$(OCAMLOPT) $(OPTFLAGS) $(INCLUDES)
OCAMLYACC_CMD=$(OCAMLYACC) -v
OCAMLDEP_CMD=$(OCAMLDEP) $(INCLUDEDIRSDEP:%=-I %)
OCAMLMKTOP_CMD=$(OCAMLMKTOP) -g -custom $(INCLUDES)

# these are unused at the moment (todo: remove)
EXTRA_CFLAGS=   # -static -pie -fpie -fPIE -static-libgcc
EXTRA_OCAML_CFLAGS=$(EXTRA_CFLAGS:%=-ccopt %)

# 'make purebytecode' unsets this definition
BYTECODE_EXTRA=-custom $(EXTRA_OCAML_FLAGS)

##############################################################################
# Top rules
##############################################################################
.PHONY:: all all.opt byte opt top clean distclean configure opt-compil
.PHONY:: $(MAKESUBDIRS:%=%.all) $(MAKESUBDIRS:%=%.opt) subdirs.all subdirs.opt
.PHONY:: all-opt all-byte byte-only opt-only


# All make targets that are expected to be an entry point have a dependency on
# 'Makefile.config' to ensure that if Makefile.config is not present, an error
# message is printed first before any other actions are executed.
# In addition, the targets that actually build something have a dependency on
# '.depend' and 'version.ml'.

# dispatches to either 'all-dev' or 'all-release'
all: Makefile.config
	@$(MAKE) .depend
	$(MAKE) $(TARGET_ALL)

# make "all" comes in three flavours
world: Makefile.config version.ml
	@echo "building both versions of spatch"
	$(MAKE) .depend
	$(MAKE) byte
	$(MAKE) opt-compil
	$(MAKE) preinstall
	$(MAKE) docs
	@echo ""
	@echo -e "\tcoccinelle can now be installed via 'make install'"

# note: the 'all-dev' target excludes the documentation
all-dev: Makefile.config version.ml
	@$(MAKE) .depend
	@echo "building the unoptimized version of spatch"
	$(MAKE) byte
	@$(MAKE) preinstall
	@echo ""
	@echo -e "\tcoccinelle can now be installed via 'make install'"

all-release: Makefile.config version.ml
	@echo building $(TARGET_SPATCH)
	$(MAKE) .depend
	$(MAKE) $(TARGET_SPATCH)
	$(MAKE) preinstall
	$(MAKE) docs
	@echo ""
	@echo -e "\tcoccinelle can now be installed via 'make install'"

all.opt: Makefile.config
	@$(MAKE) .depend
	$(MAKE) opt-only
	$(MAKE) preinstall

# aliases for "byte" and "opt-compil"
opt opt-only: Makefile.config opt-compil
byte-only: Makefile.config byte

byte: Makefile.config version.ml
	@$(MAKE) .depend
	@$(MAKE) subdirs.all
	@$(MAKE) $(EXEC)
	@echo the compilation of $(EXEC) finished
	@echo $(EXEC) can be installed or used

opt-compil: Makefile.config version.ml
	$(MAKE) .depend
	$(MAKE) subdirs.opt
	$(MAKE) $(EXEC).opt
	@echo the compilation of $(EXEC).opt finished
	@echo $(EXEC).opt can be installed or used

top: $(EXEC).top

subdirs.all:
	@+for D in $(MAKESUBDIRS); do $(MAKE) $$D.all || exit 1 ; done
	@$(MAKE) -C commons sexp.all

subdirs.opt:
	@+for D in $(MAKESUBDIRS); do $(MAKE) $$D.opt || exit 1 ; done
	@$(MAKE) -C commons sexp.opt

$(MAKESUBDIRS:%=%.all):
	@$(MAKE) -C $(@:%.all=%) all

$(MAKESUBDIRS:%=%.opt):
	@$(MAKE) -C $(@:%.opt=%) all.opt

#dependencies:
# commons:
# globals:
# menhirLib:
# parsing_cocci: commons globals menhirLib
# parsing_c:parsing_cocci
# ctl:globals commonsg
# engine: parsing_cocci parsing_c ctl
# popl09:engine
# extra: parsing_cocci parsing_c ctl
# pycaml:
# python:pycaml parsing_cocci parsing_c

clean:: Makefile.config
	@set -e; for i in $(CLEANSUBDIRS); do $(MAKE) -C $$i $@; done
	@$(MAKE) -C demos/spp $@

$(LIBS): $(MAKESUBDIRS:%=%.all)
$(LIBS:.cma=.cmxa): $(MAKESUBDIRS:%=%.opt)
$(LNKLIBS) : $(MAKESUBDIRS:%=%.all)
$(LNKOPTLIBS) : $(MAKESUBDIRS:%=%.opt)

$(OBJS):$(LIBS)
$(OPTOBJS):$(LIBS:.cma=.cmxa)

$(EXEC): $(LIBS) $(OBJS)
	$(OCAMLC_CMD) -thread $(BYTECODE_EXTRA) $(FLAGSLIBS) -o $@ $(SYSLIBS) $(LNKLIBS) $^

$(EXEC).opt: $(LIBS:.cma=.cmxa) $(OPTOBJS)
	$(OCAMLOPT_CMD) -thread $(FLAGSLIBS) -o $@ $(SYSLIBS:.cma=.cmxa) $(OPTLNKLIBS) $^

$(EXEC).top: $(LIBS) $(OBJS) $(LNKLIBS)
	$(OCAMLMKTOP_CMD) -custom -o $@ $(SYSLIBS) $(FLAGSLIBS) $(LNKLIBS) $^

clean distclean::
	rm -f $(TARGET) $(TARGET).opt $(TARGET).top

.PHONY:: tools configure

configure:
	./configure $(CONFIGURE_FLAGS)

# the dependencies on Makefile.config should give a hint to the programmer that
# configure should be run again
Makefile.config: Makefile.config.in configure.ac
	@echo "Makefile.config needs to be (re)build. Run  ./configure $(CONFIGURE_FLAGS) to generate it."
	@false

tools: $(LIBS) $(LNKLIBS)
	$(MAKE) -C tools

distclean::
	@if [ -d tools ] ; then $(MAKE) -C tools distclean ; fi

# it seems impossible to pass "-static" unless all dependent
# libraries are also available as static archives.
# set $(STATIC) to -static if you have such libraries.
static:
	rm -f spatch.opt spatch
	$(MAKE) $(STATIC) opt-only
	cp spatch.opt spatch

# This target does not work together with the bundled
# packages that contain C code. The reason is that it
# the pure bytecode requires these packages to be available
# as dynamic link library.
#
# it is, however, not clear whether this target makes
# any sense at all because it seems that it gets linked
# in custom mode anyway.
purebytecode:
	rm -f spatch.opt spatch
	$(MAKE) BYTECODE_EXTRA="" byte-only
# disabled the following command because it does not match
# perl -p -i -e 's/^#!.*/#!\/usr\/bin\/ocamlrun/' spatch

##############################################################################
# Build version information
##############################################################################

version.ml:
	@echo "version.ml is missing. Run ./configure to generate it."
	@false

##############################################################################
# Build documentation
##############################################################################
.PHONY:: docs

docs:
	@$(MAKE) -C docs || (echo "warning: ignored the failed construction of the manual" 1>&2)
	@if test "x$(FEATURE_OCAML)" = x1; then \
		if test -f ./parsing_c/ast_c.cmo; then \
			$(MAKE) -C ocaml doc; \
		else echo "note: to obtain coccilib documenation, it is required to build 'spatch' first so that ./parsing_c/ast_c.cmo gets build."; \
		fi fi
	@echo "finished building manuals"

clean:: Makefile.config
	$(MAKE) -C docs clean
	$(MAKE) -C ocaml cleandoc

##############################################################################
# Pre-Install (customization of spatch frontend script)
##############################################################################

preinstall: docs/spatch.1 scripts/spatch scripts/spatch.opt scripts/spatch.byte
	@echo "generated the wrapper scripts for spatch (the frontends)"

docs/spatch.1: Makefile.config
	$(MAKE) -C docs spatch.1

# user will use spatch to run spatch.opt (native)
scripts/spatch: Makefile.config scripts/spatch.sh
	cp scripts/spatch.sh scripts/spatch
	chmod +x scripts/spatch

# user will use spatch to run spatch (bytecode)
scripts/spatch.byte: Makefile.config scripts/spatch.sh
	cp scripts/spatch.sh scripts/spatch.byte
	chmod +x scripts/spatch.byte

# user will use spatch.opt to run spatch.opt (native)
scripts/spatch.opt: Makefile.config scripts/spatch.sh
	cp scripts/spatch.sh scripts/spatch.opt
	chmod +x scripts/spatch.opt

distclean::
	rm -f scripts/spatch scripts/spatch.byte scripts/spatch.opt

##############################################################################
# Install
##############################################################################

# don't remove DESTDIR, it can be set by package build system like ebuild
# for staged installation.
install-common:
	$(MKDIR_P) $(DESTDIR)$(BINDIR)
	$(MKDIR_P) $(DESTDIR)$(LIBDIR)
	$(MKDIR_P) $(DESTDIR)$(SHAREDIR)/ocaml
	$(MKDIR_P) $(DESTDIR)$(SHAREDIR)/commons
	$(MKDIR_P) $(DESTDIR)$(SHAREDIR)/globals
	$(MKDIR_P) $(DESTDIR)$(SHAREDIR)/parsing_c
	$(INSTALL_DATA) standard.h $(DESTDIR)$(SHAREDIR)
	$(INSTALL_DATA) standard.iso $(DESTDIR)$(SHAREDIR)
	$(INSTALL_DATA) ocaml/coccilib.cmi $(DESTDIR)$(SHAREDIR)/ocaml/
	$(INSTALL_DATA) parsing_c/*.cmi $(DESTDIR)$(SHAREDIR)/parsing_c/
	$(INSTALL_DATA) commons/*.cmi $(DESTDIR)$(SHAREDIR)/commons/
	$(INSTALL_DATA) globals/iteration.cmi $(DESTDIR)$(SHAREDIR)/globals/

install-man:
	@echo "Installing manuals in: ${DESTDIR}${MANDIR}"
	$(MKDIR_P) $(DESTDIR)$(MANDIR)/man1
	$(MKDIR_P) $(DESTDIR)$(MANDIR)/man3
	$(INSTALL_DATA) docs/spatch.1 $(DESTDIR)$(MANDIR)/man1/
	$(INSTALL_DATA) docs/Coccilib.3cocci $(DESTDIR)$(MANDIR)/man3/

install-bash:
	@echo "Installing bash completion in: ${DESTDIR}${BASH_COMPLETION_DIR}"
	$(MKDIR_P) $(DESTDIR)$(BASH_COMPLETION_DIR)
	$(INSTALL_DATA) scripts/spatch.bash_completion \
		$(DESTDIR)$(BASH_COMPLETION_DIR)/spatch

install-tools:
	@echo "Installing tools in: ${DESTDIR}${BINDIR}"
	$(MKDIR_P) $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) tools/splitpatch \
		$(DESTDIR)$(BINDIR)/splitpatch
	$(INSTALL_PROGRAM) tools/cocci-send-email.perl \
		$(DESTDIR)$(BINDIR)/cocci-send-email.perl

install-python:
	@echo "Installing python support in: ${DESTDIR}${SHAREDIR}/python"
	$(MKDIR_P) $(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_DATA) python/coccilib/*.py \
		$(DESTDIR)$(SHAREDIR)/python/coccilib
	$(INSTALL_DATA) python/coccilib/coccigui/*.py \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_DATA) python/coccilib/coccigui/pygui.glade \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_DATA) python/coccilib/coccigui/pygui.gladep \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui

install: install-man install-common $(PYTHON_INSTALL_TARGET)
	rm -f $(DESTDIR)$(SHAREDIR)/spatch
	rm -f $(DESTDIR)$(SHAREDIR)/spatch.opt
	@if test -x spatch -o -x spatch.opt; then \
		$(MAKE) install-def;fi
	@if test -x spatch ; then \
		$(MAKE) install-byte; fi
	@if test -x spatch.opt ; then \
		$(MAKE) install-opt;fi
	@if test ! -x spatch -a ! -x spatch.opt ; then \
		echo -e "\n\n\t==> Run 'make', 'make opt', or both first. <==\n\n";fi
	@echo ""
	@echo -e "\tYou can also install spatch by copying the program spatch"
	@echo -e "\t(available in this directory) anywhere you want and"
	@echo -e "\tgive it the right options to find its configuration files."
	@echo ""

#
# Installation of spatch and spatch.opt and their wrappers
#

# user will use spatch to run one of the binaries
install-def:
	$(INSTALL_PROGRAM) scripts/spatch $(DESTDIR)$(BINDIR)/spatch

# user will use spatch.byte to run spatch (bytecode)
install-byte:
	$(INSTALL_PROGRAM) spatch $(DESTDIR)$(SHAREDIR)
	$(INSTALL_PROGRAM) scripts/spatch.byte $(DESTDIR)$(BINDIR)/spatch.byte

# user will use spatch.opt to run spatch.opt (native)
install-opt:
	$(INSTALL_PROGRAM) spatch.opt $(DESTDIR)$(SHAREDIR)
	$(INSTALL_PROGRAM) scripts/spatch.opt $(DESTDIR)$(BINDIR)/spatch.opt

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/spatch
	rm -f $(DESTDIR)$(BINDIR)/spatch.opt
	rm -f $(DESTDIR)$(BINDIR)/spatch.byte
	rm -f $(DESTDIR)$(LIBDIR)/dllpycaml_stubs.so
	rm -f $(DESTDIR)$(SHAREDIR)/spatch
	rm -f $(DESTDIR)$(SHAREDIR)/spatch.opt
	rm -f $(DESTDIR)$(SHAREDIR)/standard.h
	rm -f $(DESTDIR)$(SHAREDIR)/standard.iso
	rm -f $(DESTDIR)$(SHAREDIR)/ocaml/coccilib.cmi
	rm -f $(DESTDIR)$(SHAREDIR)/parsing_c/*.cmi
	rm -f $(DESTDIR)$(SHAREDIR)/commons/*.cmi
	rm -f $(DESTDIR)$(SHAREDIR)/globals/*.cmi
	rm -f $(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui/*
	rm -f $(DESTDIR)$(SHAREDIR)/python/coccilib/*.py
	rmdir --ignore-fail-on-non-empty -p \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	rmdir $(DESTDIR)$(SHAREDIR)/globals
	rmdir $(DESTDIR)$(SHAREDIR)/commons
	rmdir $(DESTDIR)$(SHAREDIR)/parsing_c
	rmdir $(DESTDIR)$(SHAREDIR)/ocaml
	rmdir $(DESTDIR)$(SHAREDIR)
	rm -f $(DESTDIR)$(MANDIR)/man1/spatch.1
	rm -f $(DESTDIR)$(MANDIR)/man3/Coccilib.3cocci

uninstall-bash:
	rm -f $(DESTDIR)$(BASH_COMPLETION_DIR)/spatch
	rmdir --ignore-fail-on-non-empty -p \
		$(DESTDIR)$(BASH_COMPLETION_DIR)

uninstall-tools:
	rm -f $(DESTDIR)$(BINDIR)/splitpatch
	rm -f $(DESTDIR)$(BINDIR)/cocci-send-email.perl

version:
	@echo "spatch     $(VERSION)"
	@echo "spatch     $(PKGVERSION) ($(DISTRIB_ID))"
	@echo "coccicheck $(CCVERSION)"


##############################################################################
# Deb package (for Ubuntu) and release rules
##############################################################################

include Makefile.release

##############################################################################
# Developer rules
##############################################################################

-include Makefile.dev

test: $(TARGET)
	./$(TARGET) -testall

testparsing:
	./$(TARGET) -D standard.h -parse_c -dir tests/

check: scripts/spatch
	COCCINELLE_HOME="$$(pwd)" ./scripts/spatch --testall --no-update-score-file


# -inline 0  to see all the functions in the profile.
# Can also use the profile framework in commons/ and run your program
# with -profile.
forprofiling:
	$(MAKE) OPTFLAGS="-p -inline 0 ${EXTRA_OCAML_FLAGS}" opt

clean distclean::
	rm -f gmon.out

tags:
	otags -no-mli-tags -r  .

dependencygraph:
	find . -name "*.ml" |grep -v "scripts" | xargs $(OCAMLDEP) -I commons -I globals -I ctl -I parsing_cocci -I parsing_c -I engine -I popl09 -I extra > /tmp/dependfull.depend
	ocamldot -lr /tmp/dependfull.depend > /tmp/dependfull.dot
	dot -Tps /tmp/dependfull.dot > /tmp/dependfull.ps
	ps2pdf /tmp/dependfull.ps /tmp/dependfull.pdf

##############################################################################
# Misc rules
##############################################################################

# each member of the project can have its own test.ml. this file is
# not under CVS.
test.ml:
	echo "let foo_ctl () = failwith \"there is no foo_ctl formula\"" \
	  > test.ml

##############################################################################
# Generic ocaml rules
##############################################################################

.SUFFIXES: .ml .mli .cmo .cmi .cmx

.ml.cmo:
	$(OCAMLC_CMD) -c $<
.mli.cmi:
	$(OCAMLC_CMD) -c $<
.ml.cmx:
	$(OCAMLOPT_CMD) -c $<

.ml.mldepend:
	$(OCAMLC_CMD) -i $<

clean distclean::
	rm -f .depend
	rm -f *.cm[iox] *.o *.annot
	rm -f *~ .*~ *.exe #*#

distclean::
	set -e; for i in $(CLEANSUBDIRS); do $(MAKE) -C $$i $@; done
	rm -f test.ml
	rm -f TAGS
	rm -f tests/SCORE_actual.sexp
	rm -f tests/SCORE_best_of_both.sexp
	find . -name ".#*1.*" | xargs rm -f
	rm -f $(EXEC) $(EXEC).opt $(EXEC).top

# using 'touch' to prevent infinite recursion with 'make depend'
.PHONY:: depend
.depend: Makefile.config test.ml version
	@touch .depend
	@$(MAKE) depend

depend: Makefile.config test.ml version
	@echo constructing '.depend'
	@rm -f .depend
	@set -e; for i in $(MAKESUBDIRS); do $(MAKE) -C $$i depend; done
	$(OCAMLDEP_CMD) *.mli *.ml > .depend

##############################################################################
# configure-related
##############################################################################

distclean::
	@echo "cleaning configured files"
	if test -z "${KEEP_CONFIG}"; then rm -f Makefile.config; fi
	rm -rf autom4te.cache
	rm -f config.status
	rm -f config.log
	rm -f version.ml
	rm -f globals/config.ml
	rm -f globals/regexp.ml python/pycocci.ml ocaml/prepare_ocamlcocci.ml
	rm -f scripts/spatch.sh
	@echo "run 'configure' again prior to building coccinelle"


# prevent building or using dependencies when cleaning
ifneq ($(MAKECMDGOALS),clean)
ifneq ($(MAKECMDGOALS),distclean)
ifneq ($(MAKECMDGOALS),configure)
ifneq ($(MAKECMDGOALS),prerelease)
ifneq ($(MAKECMDGOALS),release)
ifneq ($(MAKECMDGOALS),package)
-include .depend
endif
endif
endif
endif
endif
endif
