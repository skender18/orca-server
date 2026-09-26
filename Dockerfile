# syntax=docker/dockerfile:1
#
# Headless Orca (stablyai/orca) runtime server for Dokploy.
#
# No official Orca server image exists, so this builds one from the release
# AppImage. The layout mirrors the project's own container test fixtures in
# config/docker/headless-pairing and config/docker/headless-serve-shutdown:
#   - the working entrypoint is resources/bin/orca-ide (NOT AppRun)
#   - the AppImage is extracted at build time (no FUSE at runtime)
#   - extraction runs as the unprivileged user so chrome-sandbox is not
#     root-owned setuid
#   - Orca starts its own Xvfb :99 when DISPLAY is unset, so the xvfb package
#     must be present but xvfb-run is not required
#   - everything runs as the non-root "orca" user, because Claude Code refuses
#     --dangerously-skip-permissions under uid 0 and Orca passes that flag

FROM ubuntu:24.04

ARG ORCA_VERSION=v1.4.212
ARG ORCA_OPENCODE_VERSION=2.0.18
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# Electron/GTK runtime libraries plus the headless plumbing. Package names
# follow the project's tested ubuntu:24.04 list; unsuffixed names resolve via
# Provides on 24.04 except libasound2, which needs the t64 name.
RUN set -eux; \
    for attempt in 1 2 3 4 5; do \
      apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=30 update && break; \
      if [ "$attempt" = 5 ]; then exit 100; fi; \
      rm -rf /var/lib/apt/lists/*; sleep 20; \
    done; \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=30 install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      dbus-x11 \
      file \
      git \
      gnupg \
      iproute2 \
      jq \
      procps \
      ripgrep \
      unzip \
      util-linux \
      xauth \
      xvfb \
      libasound2t64 \
      libatk-bridge2.0-0 \
      libatspi2.0-0 \
      libcairo2 \
      libcups2t64 \
      libdrm2 \
      libgbm1 \
      libgtk-3-0 \
      libnss3 \
      libpango-1.0-0 \
      libx11-xcb1 \
      libxcb-dri3-0 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxkbcommon0 \
      libxrandr2 \
      libxrender1 \
      libxss1 \
      libxtst6 \
    ; \
    rm -rf /var/lib/apt/lists/*

# Node.js powers the agent CLIs and the Orca skills installer.
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*; \
    node --version; npm --version

# GitHub CLI (gh) from the official repo; Orca uses it for PR/issue integration.
RUN set -eux; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get -o Acquire::Retries=5 update; \
    apt-get -o Acquire::Retries=5 install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*; \
    gh --version

# Agent CLIs. Antigravity is a single static binary installed lower down.
RUN set -eux; \
    npm install -g --no-fund --no-audit \
      "@opencode/cli@${ORCA_OPENCODE_VERSION}" \
      @anthropic-ai/claude-code \
      @openai/codex; \
    npm cache clean --force

# Dedicated unprivileged account (agents + Electron sandbox insist on it).
RUN useradd --create-home --shell /bin/bash orca

# Fetch and extract the Orca AppImage. Extraction is deliberately unprivileged.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      arm64) asset=orca-linux-arm64.AppImage ;; \
      *)     asset=orca-linux.AppImage ;; \
    esac; \
    curl -fL --retry 3 "https://github.com/stablyai/orca/releases/download/${ORCA_VERSION}/${asset}" -o /tmp/orca.AppImage; \
    chmod 0755 /tmp/orca.AppImage; \
    mkdir -p /opt/orca; \
    chown orca:orca /opt/orca; \
    cd /opt/orca; \
    runuser --user orca -- /tmp/orca.AppImage --appimage-extract >/dev/null; \
    mv squashfs-root root; \
    chmod -R a+rX /opt/orca/root; \
    rm -f /tmp/orca.AppImage; \
    test -x /opt/orca/root/resources/bin/orca-ide; \
    printf '%s\n' "${ORCA_VERSION}" > /opt/orca/VERSION

# Antigravity CLI (agy): single binary into ~/.local/bin, then surfaced on the
# system PATH so it survives the volume mount over /home/orca.
RUN set -eux; \
    runuser --user orca -- bash -lc 'curl -fsSL https://antigravity.google/cli/install.sh | bash' || true; \
    if [ -x /home/orca/.local/bin/agy ]; then install -m 0755 /home/orca/.local/bin/agy /usr/local/bin/agy; fi; \
    command -v agy || echo 'WARN: agy not installed; add it manually'

COPY entrypoint.sh /usr/local/bin/orca-entrypoint
RUN chmod 0755 /usr/local/bin/orca-entrypoint

VOLUME ["/home/orca", "/workspace"]

ENTRYPOINT ["/usr/local/bin/orca-entrypoint"]
