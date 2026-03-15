# Example: extend claudius with Flutter SDK + Android SDK
# Includes Dart — no separate Dart install needed.
# Supports: dart language-server, flutter analyze, flutter build apk/linux/web
#
# Note: iOS/Xcode builds require macOS and cannot run in a Linux container.
# Note: the Android Emulator runs on the HOST (needs KVM) — not inside this container.
#       ADB connects from the container to the host emulator via the Docker gateway.
#
# HOST SETUP (once per boot, outside claudius):
#   adb kill-server && adb -a nodaemon server &
# Then inside claudius run once:
#   adb-host
#
# Build (from repo root):
#   docker build -t claudius-flutter -f docker/claudius/flutter/Dockerfile .
#
# Use:
#   CLAUDIUS_EXTRA_VOLUMES="$HOME/.gradle:$HOME/.gradle $HOME/.pub-cache:$HOME/.pub-cache" \
#   CLAUDIUS_IMAGE=claudius-flutter claudius ~/my-flutter-project

FROM claudius

# ── Flutter SDK ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglu1-mesa \
    mesa-utils \
    openjdk-17-jdk \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    lib32stdc++6 \
    lib32z1 \
    && ln -sfn "$(dirname "$(dirname "$(readlink -f /usr/bin/java)")")" /usr/lib/jvm/default-java \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch stable \
    https://github.com/flutter/flutter.git /opt/flutter && \
    git -C /opt/flutter checkout -b stable 2>/dev/null || true && \
    git -C /opt/flutter update-ref refs/remotes/origin/stable HEAD && \
    git -C /opt/flutter branch --set-upstream-to=origin/stable stable

ENV FLUTTER_ROOT="/opt/flutter"
ENV PATH="/opt/flutter/bin:$PATH"

# Pre-download all engine artifacts (~2–3 GB). To slim down, replace with e.g.:
#   flutter precache --no-android --no-ios --no-web --no-fuchsia --no-linux-desktop --no-windows --no-macos
# Note: building for iOS additionally requires Xcode (macOS only).
RUN git config --system --add safe.directory /opt/flutter && \
    flutter config --no-analytics && \
    flutter --disable-analytics && \
    flutter precache && \
    chmod -R a+rwX /opt/flutter

# ── Android SDK ───────────────────────────────────────────────────────────────
ARG ANDROID_CMDTOOLS_VERSION=11076708
ARG ANDROID_API_LEVEL=36
ARG ANDROID_BUILD_TOOLS=35.0.0

ENV JAVA_HOME="/usr/lib/jvm/default-java"
ENV ANDROID_HOME="/opt/android-sdk"
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" && \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDTOOLS_VERSION}_latest.zip" \
        -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" && \
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" && \
    rm /tmp/cmdline-tools.zip

RUN yes | sdkmanager --licenses && \
    sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_API_LEVEL}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" && \
    chmod -R a+rwX "$ANDROID_HOME"

# ── ADB host helper ───────────────────────────────────────────────────────────
# Auto-configure adb to reach the host ADB server on every shell start.
RUN printf '\n# adb: route to host ADB server\nHOST_IP=$(ip route show default 2>/dev/null | awk '"'"'/default/ {print $3; exit}'"'"')\n[ -n "$HOST_IP" ] && export ANDROID_ADB_SERVER_ADDRESS="$HOST_IP"\nexport ANDROID_ADB_SERVER_PORT="5037"\n' >> /etc/bash.bashrc

# adb-host: manual connect + diagnostics
RUN cat > /usr/local/bin/adb-host <<'EOF'
#!/usr/bin/env bash
# Route adb commands to the host ADB server (which manages the emulator).
set -euo pipefail

CONFIG_FILE="${HOME}/.adb-host-env"

case "${1:-}" in
    list)
        [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
        adb devices -l; exit 0 ;;
    reset)
        rm -f "$CONFIG_FILE"
        echo "adb-host config removed."; exit 0 ;;
esac

HOST_IP=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
[ -n "$HOST_IP" ] || { echo "ERROR: could not determine Docker host IP" >&2; exit 1; }

export ANDROID_ADB_SERVER_ADDRESS="$HOST_IP"
export ANDROID_ADB_SERVER_PORT="5037"

printf 'ANDROID_ADB_SERVER_ADDRESS=%s\nANDROID_ADB_SERVER_PORT=5037\n' "$HOST_IP" > "$CONFIG_FILE"

if ! grep -q "adb-host-env" "${HOME}/.bashrc" 2>/dev/null; then
    printf '\n# adb-host\n[ -f ~/.adb-host-env ] && . ~/.adb-host-env\n' >> "${HOME}/.bashrc"
fi

echo "Routing adb → host ADB server at $HOST_IP:5037"
adb devices -l || {
    echo ""
    echo "Cannot reach host ADB server. On the HOST run:"
    echo "  adb kill-server && adb -a nodaemon server &"
    exit 1
}
EOF
RUN chmod +x /usr/local/bin/adb-host
