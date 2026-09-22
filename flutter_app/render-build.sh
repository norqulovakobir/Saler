#!/usr/bin/env bash
# Render Static Site build: Flutter SDK'ni yuklab, web versiyani build qiladi.
# Env (Render -> Environment): API_BASE, BOT_USERNAME (ixtiyoriy, default qiymatlar bor).
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$PWD/flutter}"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-$PWD/.pub-cache}"

flutter config --no-analytics --enable-web >/dev/null
flutter --version
flutter pub get
flutter build web --release \
  --dart-define=API_BASE="${API_BASE:-https://saler-api.akobirnorqulov104.workers.dev}" \
  --dart-define=REALTIME_ENABLED="${REALTIME_ENABLED:-false}" \
  --dart-define=BOT_USERNAME="${BOT_USERNAME:-saler_ai_bot}" \
  --dart-define=APP_VERSION="${RENDER_GIT_COMMIT:-1.0.0}"
