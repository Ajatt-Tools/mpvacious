PROJECT     := mpvacious
PREFIX      ?= /etc/mpv/
BRANCH      ?= remotes/origin/master
VERSION     := $(shell git describe --tags $(BRANCH))
RELEASE_DIR := .github/RELEASE
ZIP         := $(RELEASE_DIR)/$(PROJECT)_$(VERSION).zip
DOCS        := $(RELEASE_DIR)/README_$(VERSION).html
MD2HTML      = md2html --github --full-html

.PHONY: all clean docs install uninstall

all: $(ZIP)
docs: $(DOCS)

$(ZIP):
	git archive \
	--prefix=$(PROJECT)_$(VERSION)/ \
	--format=zip \
	-o $@ \
	$(BRANCH) \

$(DOCS):
	git show "$(BRANCH):README.md" | $(MD2HTML) -o $@

install:
	find . -type f -iname '*.lua' | while read -r file; do \
		install -Dm644 "$$file" "$(PREFIX)/scripts/$(PROJECT)/$$file"; \
	done
	install -Dm644 $(RELEASE_DIR)/subs2srs.conf "$(PREFIX)/script-opts/subs2srs.conf"

uninstall:
	rm -rf -- "$(PREFIX)/scripts/$(PROJECT)"
	rm -- "$(PREFIX)/script-opts/subs2srs.conf"

clean:
	rm -- $(ZIP) $(DOCS)
