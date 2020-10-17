PROJECT = mpvacious
VERSION = v0.3
MD2HTML = md2html --github --full-html
ZIPNAME = $(PROJECT)_$(VERSION).zip
OBJECTS = windows linux LICENSE

LINUXBRANCH = remotes/origin/master
WINDOWSBRANCH = remotes/origin/windows

.PHONY: clean all windows linux

all: $(ZIPNAME)

$(ZIPNAME): $(OBJECTS)
	zip -r $(ZIPNAME) -- $^

linux:
	mkdir -p -- ./$@
	git show "$(LINUXBRANCH):subs2srs.lua" > ./$@/$(PROJECT)_$@_$(VERSION).lua
	git show "$(LINUXBRANCH):README.md" | $(MD2HTML) -o ./$@/readme_$@.html

windows:
	mkdir -p -- ./$@
	git show "$(WINDOWSBRANCH):subs2srs.lua" > ./$@/$(PROJECT)_$@_$(VERSION).lua
	git show "$(WINDOWSBRANCH):README.md" | $(MD2HTML) -o ./$@/readme_$@.html

LICENSE:
	git show "master:$@" > $@

clean:
	rm -rf -- $(OBJECTS) ./*.zip
