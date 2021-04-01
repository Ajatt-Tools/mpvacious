PROJECT = mpvacious
VERSION = v0.14
MD2HTML = md2html --github --full-html
ZIP     = $(PROJECT)_$(VERSION).zip
SCRIPT  = $(PROJECT)_$(VERSION).lua
BRANCH  = remotes/origin/master

.PHONY: all clean

all: $(ZIP)

$(ZIP): $(PROJECT)
	zip -r $@ -- $^

$(PROJECT):
	mkdir -p -- ./$@
	git show "$(BRANCH):subs2srs.lua" > ./$@/$(SCRIPT)
	git show "$(BRANCH):README.md" | $(MD2HTML) -o ./$@/README_$(VERSION).html
	git show "$(BRANCH):LICENSE" > ./$@/LICENSE

clean:
	rm -rf -- ./$(PROJECT)*
