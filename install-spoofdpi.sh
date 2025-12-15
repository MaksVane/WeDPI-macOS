#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}        SpoofDPI install (WeDPI)        ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARCH_NAME="arm64" ;;
  x86_64) ARCH_NAME="amd64" ;;
  *) echo -e "${RED}Неподдерживаемая архитектура: $ARCH${NC}"; exit 1 ;;
esac

METHOD=""
if command -v go &> /dev/null; then
  METHOD="go"
fi
if command -v brew &> /dev/null && [ -z "$METHOD" ]; then
  METHOD="brew"
fi

echo -e "${GREEN}✓${NC} Архитектура: $ARCH_NAME"
if command -v go &> /dev/null; then echo -e "${GREEN}✓${NC} Go: $(go version)"; fi
if command -v brew &> /dev/null; then echo -e "${GREEN}✓${NC} Homebrew: найден"; fi
echo ""

echo "Выберите способ установки:"
if command -v go &> /dev/null; then echo "  1) Go (рекомендуется)"; fi
if command -v brew &> /dev/null; then echo "  2) Homebrew"; fi
echo "  3) Скачать бинарник"
echo ""

read -p "Выбор [1]: " choice
choice=${choice:-1}

case "$choice" in
  1) METHOD="go" ;;
  2) METHOD="brew" ;;
  *) METHOD="binary" ;;
esac

case "$METHOD" in
  go)
    if ! command -v go &> /dev/null; then
      echo -e "${RED}Go не найден.${NC}"
      exit 1
    fi
    echo -e "${BLUE}Установка через Go...${NC}"
    go install github.com/xvzc/SpoofDPI/cmd/spoofdpi@latest
    GOPATH="$(go env GOPATH)"
    BIN_SRC="$GOPATH/bin/spoofdpi"
    if [ ! -f "$BIN_SRC" ]; then BIN_SRC="$HOME/go/bin/spoofdpi"; fi
    if [ ! -f "$BIN_SRC" ]; then echo -e "${RED}spoofdpi не найден после установки${NC}"; exit 1; fi
    echo "Копирование в /usr/local/bin (нужен пароль)..."
    sudo cp "$BIN_SRC" /usr/local/bin/spoofdpi
    sudo chmod +x /usr/local/bin/spoofdpi
    ;;
  brew)
    if ! command -v brew &> /dev/null; then
      echo -e "${RED}Homebrew не найден.${NC}"
      exit 1
    fi
    echo -e "${BLUE}Установка через Homebrew...${NC}"
    brew tap xvzc/tap 2>/dev/null || true
    brew install spoofdpi || {
      echo -e "${YELLOW}Формулы нет — ставим через Go...${NC}"
      brew install go
      go install github.com/xvzc/SpoofDPI/cmd/spoofdpi@latest
      GOPATH="$(go env GOPATH)"
      sudo cp "$GOPATH/bin/spoofdpi" /usr/local/bin/spoofdpi
      sudo chmod +x /usr/local/bin/spoofdpi
    }
    ;;
  binary)
    if ! command -v curl &> /dev/null; then
      echo -e "${RED}curl не найден.${NC}"
      exit 1
    fi
    echo -e "${BLUE}Скачивание бинарника...${NC}"
    LATEST="$(curl -s https://api.github.com/repos/xvzc/SpoofDPI/releases/latest | grep '\"tag_name\"' | sed -E 's/.*\"([^\"]+)\".*/\\1/')"
    if [ -z "$LATEST" ]; then echo -e "${RED}Не удалось получить версию релиза${NC}"; exit 1; fi
    URL="https://github.com/xvzc/SpoofDPI/releases/download/${LATEST}/spoofdpi-darwin-${ARCH_NAME}"
    curl -L -o /tmp/spoofdpi "$URL"
    sudo mv /tmp/spoofdpi /usr/local/bin/spoofdpi
    sudo chmod +x /usr/local/bin/spoofdpi
    ;;
esac

echo ""
if command -v spoofdpi &> /dev/null; then
  echo -e "${GREEN}✓${NC} Установлено: $(command -v spoofdpi)"
  spoofdpi -v 2>/dev/null || true
else
  echo -e "${RED}SpoofDPI не найден после установки${NC}"
  exit 1
fi

