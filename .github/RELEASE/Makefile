PROJECT     = mpvacious
VERSION     = v0.21
MD2HTML     = md2html --github --full-html
ZIP         = $(PROJECT)_$(VERSION).zip
BRANCH      ?= remotes/origin/master
DOCS        = README_$(VERSION).html
RELEASE_DIR = .github/RELEASE

.PHONY: all clean docs

all: $(ZIP)
docs: $(DOCS)

$(ZIP): $(DOCS)
	cd -- "$$(git rev-parse --show-toplevel)" && \
	git archive \
	--prefix=$(PROJECT)_$(VERSION)/ \
	--format=zip \
	-o $(RELEASE_DIR)/$@ \
	--add-file=$(RELEASE_DIR)/$(DOCS) \
	$(BRANCH) \

$(DOCS):
	git show "$(BRANCH):README.md" | $(MD2HTML) -o $@

clean:
	rm -- $(ZIP) $(DOCS)
