IMAGE   := claudius
BINDIR  := $(HOME)/.local/bin

.PHONY: build rebuild install uninstall help

help:
	@echo "Usage:"
	@echo "  make build      – build image (cached)"
	@echo "  make rebuild    – build image (no cache, updates Claude Code)"
	@echo "  make install    – symlink 'claudius' into $(BINDIR)"
	@echo "  make uninstall  – remove the symlink"

build:
	docker build -t $(IMAGE) -f docker/claudius/Dockerfile .

rebuild:
	docker build --no-cache -t $(IMAGE) -f docker/claudius/Dockerfile .

install:
	@mkdir -p $(BINDIR)
	@ln -sf $(CURDIR)/claudius.sh $(BINDIR)/claudius
	@chmod +x $(CURDIR)/claudius.sh
	@echo "✓ claudius → $(BINDIR)/claudius"
	@which claudius >/dev/null 2>&1 || { echo ""; echo "  Note: add $(BINDIR) to PATH – run: export PATH=\"$(BINDIR):\$$PATH\""; }

uninstall:
	@rm -f $(BINDIR)/claudius
	@echo "✓ claudius removed ($(BINDIR)/claudius)"
