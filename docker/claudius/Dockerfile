FROM docker:cli AS docker-cli

FROM node:20-bookworm-slim

LABEL org.opencontainers.image.title="claude-box"
LABEL org.opencontainers.image.description="Sandboxed Claude Code environment"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    vim \
    less \
    gnupg \
    iptables \
    iputils-ping \
    mtr-tiny \
    openssh-client \
    iproute2 \
    dnsutils \
    ca-certificates \
    procps \
    util-linux \
    gosu \
    jq \
    lsof \
    make \
    netcat-openbsd \
    python3 \
    python3-pip \
    sqlite3 \
    strace \
    sudo \
    tree \
    unzip \
    wl-clipboard \
    xclip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

# Claude Code – native installer, then move to system paths accessible to all users.
# The installer creates ~/.local/bin/claude as a symlink into ~/.local/share/claude/versions/X;
# after moving the share dir we repoint the symlink accordingly.
RUN export PATH="$HOME/.local/bin:$PATH" && \
    curl -fsSL https://claude.ai/install.sh | bash && \
    mv /root/.local/share/claude /usr/local/share/claude && \
    ln -sf "$(readlink /root/.local/bin/claude | sed 's|/root/.local/share/claude|/usr/local/share/claude|')" \
       /usr/local/bin/claude && \
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true && \
    npm config set prefix /opt/npm

# Starship prompt
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Shell config: PATH + starship
RUN printf '\n# claudius\nexport PATH="$HOME/.local/bin:$PATH"\neval "$(starship init bash)"\n' >> /root/.bashrc

RUN mkdir -p /root/.config
COPY docker/claudius/starship.toml /root/.config/starship.toml

# Pre-seed GitHub's SSH host key so git push/pull never prompts.
RUN ssh-keyscan -t ed25519 github.com >> /etc/ssh/ssh_known_hosts

WORKDIR /workspace

COPY docker/claudius/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY docker/claudius/entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN mkdir -p /etc/claude-code
COPY CLAUDE.md /etc/claude-code/CLAUDE.md
RUN chmod 444 /etc/claude-code/CLAUDE.md && \
    chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh && \
    passwd -l root

ENV TERM=xterm-256color
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV COLORTERM=truecolor
ENV DISABLE_AUTOUPDATER=1
ENV NPM_CONFIG_PREFIX=/opt/npm

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
