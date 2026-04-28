IMAGE  := claudius
BINDIR := $(HOME)/.local/bin

.PHONY: build rebuild install uninstall gvisor-install gvisor-configure gvisor-uninstall gvisor-check rootless-check test-integration help

help:
	@echo "Usage:"
	@echo "  make build              – build image (cached)"
	@echo "  make rebuild            – build image (no cache, updates Claude Code)"
	@echo "  make install            – symlink 'claudius' into $(BINDIR)"
	@echo "  make uninstall          – remove the symlink"
	@echo "  make test-integration   – end-to-end network filtering tests"
	@echo "  make gvisor-install     – install gVisor (runsc) runtime on the host"
	@echo "  make gvisor-configure   – configure runsc daemon flags (no reinstall)"
	@echo "  make gvisor-uninstall   – remove gVisor runtime"
	@echo "  make gvisor-check       – verify gVisor installation"
	@echo "  make rootless-check     – verify Docker is running rootless (recommended)"

test-integration:
	@bash tests/integration.sh

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

gvisor-install:
	sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
	curl -fsSL https://gvisor.dev/archive.key \
	  | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
	echo "deb [arch=$$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] \
	  https://storage.googleapis.com/gvisor/releases release main" \
	  | sudo tee /etc/apt/sources.list.d/gvisor.list
	sudo apt-get update && sudo apt-get install -y runsc
	$(MAKE) gvisor-configure
	@echo "✓ gVisor installed – use CLAUDIUS_RUNTIME=runsc"

gvisor-configure:
	sudo runsc install -- --host-uds=open --network=sandbox
	sudo systemctl reload docker
	@echo "✓ gVisor configured (host-uds=open, network=sandbox)"

gvisor-uninstall:
	sudo apt-get remove -y runsc
	sudo rm -f /usr/share/keyrings/gvisor-archive-keyring.gpg \
	           /etc/apt/sources.list.d/gvisor.list
	sudo apt-get update
	@echo "✓ gVisor removed"

rootless-check:
	@echo "── Docker daemon user ────────────────────────"
	@docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q 'rootless' \
	  && echo "✓ Docker is running rootless" \
	  || { echo "✗ Docker is NOT rootless"; \
	       echo "  Host-root blast radius if the sandbox ever escapes."; \
	       echo "  See: https://docs.docker.com/engine/security/rootless/"; \
	       echo "  Install:  dockerd-rootless-setuptool.sh install"; \
	       exit 1; }
	@echo "── socket location ───────────────────────────"
	@test -S "$${XDG_RUNTIME_DIR:-/run/user/$$(id -u)}/docker.sock" \
	  && echo "✓ rootless socket at $${XDG_RUNTIME_DIR:-/run/user/$$(id -u)}/docker.sock" \
	  || echo "⚠ rootless socket not found at expected path (check DOCKER_HOST)"
	@echo "✓ rootless OK"

gvisor-check:
	@echo "── runsc binary ──────────────────────────────"
	@runsc --version 2>/dev/null || { echo "✗ runsc not found"; exit 1; }
	@echo "── Docker runtime ────────────────────────────"
	@docker info 2>/dev/null | grep -i runsc && echo "✓ Docker knows runsc" \
	  || { echo "✗ runsc not registered in Docker"; exit 1; }
	@echo "── host-uds=open ─────────────────────────────"
	@cat /etc/docker/daemon.json 2>/dev/null | grep -q 'host-uds' \
	  && echo "✓ host-uds configured" \
	  || { echo "✗ host-uds not set – run: make gvisor"; exit 1; }
	@echo "── network=sandbox ───────────────────────────"
	@cat /etc/docker/daemon.json 2>/dev/null | grep -q 'network.*sandbox' \
	  && echo "✓ network=sandbox configured" \
	  || { echo "✗ network=sandbox not set – run: make gvisor"; exit 1; }
	@echo "── smoke test ────────────────────────────────"
	docker run --rm --runtime=runsc hello-world
	@echo "✓ gVisor OK"

