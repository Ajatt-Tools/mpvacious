PROJECT     := mpvacious
PACKAGE     := subs2srs
# PREFIX is a path to the mpv config directory,
# e.g. ~/.config/mpv/ or $pkgdir/etc/mpv when using PKGBUILD
PREFIX      ?= $(HOME)/.config/mpv
BRANCH      ?= master
VERSION     ?= $(shell git describe --tags $(BRANCH))
RELEASE_DIR := .github/RELEASE
ZIP         := $(RELEASE_DIR)/$(PROJECT)_$(VERSION).zip
DOCS        := $(RELEASE_DIR)/README_$(VERSION).html
MD2HTML      = md2html --github --full-html

EXAMPLE_CONFIG      := $(PROJECT)/config/default_config.conf
EXAMPLE_CONFIG_COPY := $(RELEASE_DIR)/$(PACKAGE).conf

.PHONY: all docs install uninstall clean

all: $(ZIP) $(EXAMPLE_CONFIG_COPY)
docs: $(DOCS)

$(ZIP):
	git archive \
	--prefix=$(PROJECT)/ \
	--format=zip \
	--output $@ \
	"$(BRANCH):$(PROJECT)"

$(EXAMPLE_CONFIG_COPY): $(EXAMPLE_CONFIG)
	cp -- "$<" "$@"

$(DOCS):
	git show "$(BRANCH):README.md" | $(MD2HTML) -o $@

install:
	@echo "Installing $(PROJECT) to $(PREFIX)/scripts/$(PROJECT)/"
	install -d "$(PREFIX)/scripts/$(PROJECT)/"
	# Copy directory contents preserving attributes
	cp -a -- "./$(PROJECT)" "$(PREFIX)/scripts/"
	if [ ! -f "$(PREFIX)/script-opts/$(PACKAGE).conf" ]; then \
		install -Dm644 "$(EXAMPLE_CONFIG)" "$(PREFIX)/script-opts/$(PACKAGE).conf"; \
	fi

uninstall:
	rm -rf -- "$(PREFIX)/scripts/$(PROJECT)"

clean:
	rm -v -- "$(ZIP)" "$(DOCS)" "$(EXAMPLE_CONFIG_COPY)" || true
