# general Makefile for compiling Sourcemod plugins
# copyright (c) 2021 https://github.com/CrimsonTautology

SHELL=/bin/bash

# directories
override scripting_dir=addons/sourcemod/scripting
override include_dir=addons/sourcemod/scripting/include
override testing_dir=addons/sourcemod/scripting/testsuite
override plugins_dir=addons/sourcemod/plugins
override testsuite_dir=addons/sourcemod/plugins/testsuite
override configs_dir=addons/sourcemod/configs
override extensions_dir=addons/sourcemod/extensions
override gamedata_dir=addons/sourcemod/gamedata
override translations_dir=addons/sourcemod/translations

# spcomp
SPCOMP=spcomp
INC=-i$(include_dir)
SPFLAGS=
DEBUG=

# other programs
CTAGS=ctags
DOS2UNIX=dos2unix
ZIP=zip

# files
override sourcefiles=$(wildcard $(scripting_dir)/*.sp)
override includefiles=$(shell find $(include_dir) -name '*.inc' 2>/dev/null)
override testfiles=$(wildcard $(testing_dir)/test_*.sp)

override plugins=\
	$(patsubst $(scripting_dir)/%.sp, $(plugins_dir)/%.smx, $(sourcefiles))

override testsuite=\
	$(patsubst $(testing_dir)/%.sp, $(testsuite_dir)/%.smx, $(testfiles))

override configs=\
	$(shell find $(configs_dir) -name '*' -type f 2>/dev/null)

override extensions=\
	$(shell find $(extensions_dir) -name '*.so' -type f 2>/dev/null)

override gamedata=\
	$(shell find $(gamedata_dir) -name '*.txt' -type f 2>/dev/null)

override translations=\
	$(shell find $(translations_dir) -name '*.phrases.txt' -type f 2>/dev/null)

override release_files=README.md LICENSE Makefile addons cfg materials

# installation
SRCDS=/tmp
override disabled=$(addprefix $(plugins_dir)/,\
	$(notdir $(wildcard $(SRCDS)/$(plugins_dir)/disabled/*.smx)))

vpath %.sp $(scripting_dir)
vpath %.sp $(testing_dir)

ifeq ($(DEBUG), 1)
	SPFLAGS+=DEBUG=1
endif

all: clean compile tags

$(plugins_dir)/%.smx: %.sp | $(plugins_dir)
	$(SPCOMP) $^ -o$@ $(INC) $(SPFLAGS)

$(plugins_dir)/%.asm: %.sp | $(plugins_dir)
	$(SPCOMP) $^ -o$@ $(INC) $(SPFLAGS) -a

$(plugins_dir)%.lst: %.sp | $(plugins_dir)
	$(SPCOMP) $^ -o$@ $(INC) $(SPFLAGS) -l

$(plugins_dir):
	mkdir -p $@

clean:
	$(RM) -r $(plugins_dir)

compile: $(plugins)

tags:
	-$(CTAGS) --langmap=c:+.sp,c:+.inc --recurse

dos2unix:
	$(DOS2UNIX) $(sourcefiles) $(includefiles) $(configs) $(gamedata) $(translations)

list:
	@printf 'plugins:\n'
	@printf '%s\n' $(plugins)
	@printf '\ndisabled plugins on install server:\n'
	@printf '%s\n' $(disabled)
	@printf '\nsource files:\n'
	@printf '%s\n' $(sourcefiles)
	@printf '\ninclude files:\n'
	@printf '%s\n' $(includefiles)
	@printf '\ntestsuite:\n'
	@printf '%s\n' $(testsuite)
	@printf '\ntest files:\n'
	@printf '%s\n' $(testfiles)
	@printf '\nconfigs:\n'
	@printf '%s\n' $(configs)
	@printf '\ngamedata:\n'
	@printf '%s\n' $(gamedata)
	@printf '\nextensions:\n'
	@printf '%s\n' $(extensions)
	@printf '\ntranslation:\n'
	@printf '%s\n' $(translations)

install:
	@# install only plugins that are not in the 'disabled' folder
	@$(foreach file, $(filter-out $(disabled), $(plugins)),\
		cp --parents $(file) -t $(SRCDS);)
	@if [ -n "$(configs)" ]; then cp -n --parents $(configs) -t $(SRCDS); fi
	@if [ -n "$(extensions)" ]; then cp -n --parents $(extensions) -t $(SRCDS); fi
	@if [ -n "$(gamedata)" ]; then cp --parents $(gamedata) -t $(SRCDS); fi
	@if [ -n "$(translations)" ]; then cp --parents $(translations) -t $(SRCDS); fi
	@echo "install $(notdir $(filter-out $(disabled), $(plugins)) $(extensions)) to $(SRCDS)"

uninstall:
	@$(RM) \
		$(addprefix $(SRCDS)/, $(plugins)) \
		$(addprefix $(SRCDS)/, $(configs)) \
		$(addprefix $(SRCDS)/, $(gamedata)) \
		$(addprefix $(SRCDS)/, $(translations))
	@echo "uninstall $(notdir $(plugins)) from $(SRCDS)"

$(testsuite_dir)/%.smx: %.sp | $(testsuite_dir)
	$(SPCOMP) $^ -o$@ $(INC) $(SPFLAGS)

$(testsuite_dir):
	mkdir -p $@

test: $(testsuite)

test-install: test
	cp --parents $(testsuite) -t $(SRCDS)

test-uninstall:
	$(RM) $(addprefix $(SRCDS)/, $(testsuite))

release.tar.gz: compile
	tar cvzf $@ $(release_files) --ignore-failed-read

release.zip: compile
	$(ZIP) -r $@ $(release_files)

.PHONY: all clean compile tags dos2unix list install uninstall test\
	test-install test-uninstall
