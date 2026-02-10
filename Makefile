PROJECT     := mpvacious
PACKAGE     := subs2srs
# PREFIX is a path to the mpv config directory,
# e.g. ~/.config/mpv/ or $pkgdir/etc/mpv when using PKGBUILD
PREFIX      ?= ~/.config/mpv
BRANCH      ?= master
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
	--output $@ \
	"$(BRANCH):$(PROJECT)" \

$(DOCS):
	git show "$(BRANCH):README.md" | $(MD2HTML) -o $@

install:
	@echo "Installing $(PROJECT) to $(PREFIX)/scripts/$(PROJECT)/"
	install -d "$(PREFIX)/scripts/$(PROJECT)/"
	# Copy directory contents preserving attributes
	cp -a -- "./$(PROJECT)" "$(PREFIX)/scripts/"
	install -Dm644 "$(RELEASE_DIR)/$(PACKAGE).conf" "$(PREFIX)/script-opts/$(PACKAGE).conf"

uninstall:
	rm -rf -- "$(PREFIX)/scripts/$(PROJECT)"
	rm -- "$(PREFIX)/script-opts/$(PACKAGE).conf"

clean:
	rm -- $(ZIP) $(DOCS)
