PROJECT     := mpvacious
PACKAGE     := subs2srs
PREFIX      ?= /etc/mpv/
BRANCH      ?= remotes/origin/master
VERSION     := $(shell git describe --tags $(BRANCH))
RELEASE_DIR := .github/RELEASE
ZIP         := $(RELEASE_DIR)/$(PROJECT)_$(VERSION).zip
DOCS        := $(RELEASE_DIR)/README_$(VERSION).html
MD2HTML      = md2html --github --full-html

.PHONY: all docs install uninstall clean

all: $(ZIP)
docs: $(DOCS)

$(ZIP):
	git archive \
	--prefix=$(PROJECT)/ \
	--format=zip \
	-o $@ \
	$(BRANCH) \

$(DOCS):
	git show "$(BRANCH):README.md" | $(MD2HTML) -o $@

install:
	find . -type f -regextype posix-extended -iregex '.*\.(lua|json|conf)$$' | while read -r file; do \
		install -Dm644 "$$file" "$(PREFIX)/scripts/$(PROJECT)/$$file"; \
	done
	install -Dm644 "$(RELEASE_DIR)/$(PACKAGE).conf" "$(PREFIX)/script-opts/$(PACKAGE).conf"

uninstall:
	rm -rf -- "$(PREFIX)/scripts/$(PROJECT)"
	rm -- "$(PREFIX)/script-opts/$(PACKAGE).conf"

clean:
	rm -- $(ZIP) $(DOCS)
