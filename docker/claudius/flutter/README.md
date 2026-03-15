# claudius-flutter

Flutter + Android SDK development image for claudius.

**Supports:** Android (via host emulator), Linux desktop, Web (via web-server)
**Does not support:** iOS (requires macOS/Xcode)

## Build

From the claudius repo root:

```bash
docker build -t claudius-flutter -f docker/claudius/flutter/Dockerfile .
```

## Use

```bash
CLAUDIUS_EXTRA_VOLUMES="$HOME/.gradle:$HOME/.gradle $HOME/.pub-cache:$HOME/.pub-cache" \
CLAUDIUS_IMAGE=claudius-flutter claudius ~/my-flutter-project
```

The Gradle and pub caches are mounted from the host so they persist across container restarts.

## Android Emulator

The emulator runs on the **host** (needs KVM). ADB connects to it via the Docker gateway.

**Host setup (once per boot):**

```bash
adb kill-server && adb -a nodaemon server &
```

The container automatically routes ADB to the host on every shell start.
Use `adb-host` inside the container to verify the connection.

## Web

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Open `http://<host-ip>:8080` in the host browser.
Note: add web support first if missing: `flutter create --platforms web .`
