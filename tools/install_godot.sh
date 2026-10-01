#!/usr/bin/env bash
# 在雲端 session（Claude Code on the web）安裝 Godot headless，供 tools/godot_check.sh 使用。
# 本機執行時直接略過；已安裝過則不重複下載。
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
INSTALL_DIR="$HOME/.cache/godot/$GODOT_VERSION"
BIN="$INSTALL_DIR/godot"

if [ ! -x "$BIN" ]; then
  ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  # 官方下載站優先；雲端的 GitHub proxy 可能擋下其他 repo 的 release 檔案，所以 GitHub 只當備援
  URLS=(
    "https://downloads.godotengine.org/?version=${GODOT_VERSION}&flavor=stable&slug=linux.x86_64.zip&platform=linux.64"
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${ZIP}"
  )
  TMP="$(mktemp -d)"
  ok=""
  for url in "${URLS[@]}"; do
    if curl -fsSL --retry 2 -o "$TMP/$ZIP" "$url"; then ok=1; break; fi
    echo "[install_godot] 下載失敗：$url" >&2
  done
  if [ -z "$ok" ]; then
    echo "[install_godot] 無法下載 Godot。請把雲端環境的網路設為 Custom，並加入 downloads.godotengine.org 與 godot-releases.nbg1.your-objectstorage.com" >&2
    exit 0  # 不阻擋 session 啟動
  fi
  mkdir -p "$INSTALL_DIR"
  unzip -qo "$TMP/$ZIP" -d "$TMP"
  mv "$TMP/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$BIN"
  chmod +x "$BIN"
  rm -rf "$TMP"
fi

if [ -w /usr/local/bin ]; then
  ln -sf "$BIN" /usr/local/bin/godot
fi
echo "[install_godot] Godot $("$BIN" --version 2>/dev/null) 已就緒：$BIN"
