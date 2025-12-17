#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="WeDPI"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

status() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

tail_log() {
    local file="$1"
    local lines="${2:-120}"
    if [ -f "$file" ]; then
        echo ""
        echo -e "${YELLOW}Последние строки лога ($file):${NC}"
        tail -n "$lines" "$file" || true
    fi
}

print_xcodebuild_errors() {
    local file="$1"
    if [ -f "$file" ]; then
        echo ""
        echo -e "${YELLOW}Ошибки из лога ($file):${NC}"
        grep -E "(^|\\s)(error:|fatal error:|ARCHIVE FAILED)" "$file" | tail -n 120 || true
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}           WeDPI - Build               ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if ! command -v xcodebuild &> /dev/null; then
    warn "xcodebuild не найден."
    if [ -d "/Applications/Xcode.app" ]; then
        echo "Xcode найден. Переключаем на него (нужен пароль)..."
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
    else
        error "Установите Xcode и повторите."
    fi
fi

if ! command -v swift &> /dev/null; then
    error "Swift не найден. Установите Xcode."
fi

status "Swift: $(swift --version | head -1)"

SPOOFDPI_PATH=""
if [ -f "/opt/homebrew/bin/spoofdpi" ]; then
    SPOOFDPI_PATH="/opt/homebrew/bin/spoofdpi"
elif [ -f "/usr/local/bin/spoofdpi" ]; then
    SPOOFDPI_PATH="/usr/local/bin/spoofdpi"
elif [ -f "$HOME/.local/bin/spoofdpi" ]; then
    SPOOFDPI_PATH="$HOME/.local/bin/spoofdpi"
elif command -v spoofdpi &> /dev/null; then
    SPOOFDPI_PATH="$(command -v spoofdpi)"
fi

if [ -n "$SPOOFDPI_PATH" ]; then
    status "SpoofDPI: $SPOOFDPI_PATH"
else
    warn "SpoofDPI не найден. Приложение соберётся, но без встроенного бинарника."
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

XCODEBUILD_LOG="$BUILD_DIR/xcodebuild.log"
DMG_LOG="$BUILD_DIR/dmg.log"

echo ""
echo -e "${BLUE}[1/3]${NC} Сборка приложения..."

cd "$SCRIPT_DIR"
{
    xcodebuild -project WeDPI.xcodeproj \
        -scheme WeDPI \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        -archivePath "$BUILD_DIR/WeDPI.xcarchive" \
        -destination "generic/platform=macOS" \
        -quiet \
        archive \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
} >"$XCODEBUILD_LOG" 2>&1 || {
    print_xcodebuild_errors "$XCODEBUILD_LOG"
    error "Сборка не удалась (см. лог: $XCODEBUILD_LOG)"
}

status "Сборка завершена"

echo ""
echo -e "${BLUE}[2/3]${NC} Подготовка .app..."

BUILT_APP="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    BUILT_APP="$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)"
fi
if [ -z "$BUILT_APP" ] || [ ! -d "$BUILT_APP" ]; then
    error "Не найден собранный $APP_NAME.app"
fi

cp -r "$BUILT_APP" "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/Resources/lists"

if [ -n "$SPOOFDPI_PATH" ]; then
    cp "$SPOOFDPI_PATH" "$APP_BUNDLE/Contents/MacOS/spoofdpi"
    chmod +x "$APP_BUNDLE/Contents/MacOS/spoofdpi"
    status "SpoofDPI добавлен в .app"
fi

if [ -d "WeDPI/Resources/lists" ]; then
    cp -r WeDPI/Resources/lists/* "$APP_BUNDLE/Contents/Resources/lists/" 2>/dev/null || true
fi

generate_and_install_icns() {
    local app_bundle="$1"
    local svg_path="$2"

    if [ ! -f "$svg_path" ]; then
        return 0
    fi
    if ! command -v qlmanage &> /dev/null || ! command -v sips &> /dev/null || ! command -v iconutil &> /dev/null; then
        warn "Не хватает утилит для генерации иконки (qlmanage/sips/iconutil)."
        return 0
    fi

    local icon_build_dir="$BUILD_DIR/icon_build"
    local iconset_dir="$icon_build_dir/AppIcon.iconset"
    local icns_path="$icon_build_dir/AppIcon.icns"
    rm -rf "$icon_build_dir"
    mkdir -p "$iconset_dir"

    qlmanage -t -s 1024 -o "$icon_build_dir" "$svg_path" > /dev/null 2>&1 || true
    local rendered_png
    rendered_png="$(find "$icon_build_dir" -maxdepth 1 -type f -name "*.png" | head -1)"
    if [ -z "$rendered_png" ]; then
        warn "Не удалось отрендерить $svg_path"
        rm -rf "$icon_build_dir"
        return 0
    fi

    cp "$rendered_png" "$iconset_dir/icon_512x512@2x.png"
    sips -z 512 512  "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_512x512.png"    > /dev/null
    sips -z 512 512  "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_256x256@2x.png" > /dev/null
    sips -z 256 256  "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_256x256.png"    > /dev/null
    sips -z 256 256  "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_128x128@2x.png" > /dev/null
    sips -z 128 128  "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_128x128.png"    > /dev/null
    sips -z 64 64    "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_32x32@2x.png"   > /dev/null
    sips -z 32 32    "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_32x32.png"      > /dev/null
    sips -z 32 32    "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_16x16@2x.png"   > /dev/null
    sips -z 16 16    "$iconset_dir/icon_512x512@2x.png" --out "$iconset_dir/icon_16x16.png"      > /dev/null

    iconutil -c icns "$iconset_dir" -o "$icns_path" > /dev/null 2>&1 || true
    if [ ! -f "$icns_path" ]; then
        warn "Не удалось собрать AppIcon.icns"
        rm -rf "$icon_build_dir"
        return 0
    fi

    mkdir -p "$app_bundle/Contents/Resources"
    cp "$icns_path" "$app_bundle/Contents/Resources/AppIcon.icns"

    local plist="$app_bundle/Contents/Info.plist"
    if [ -f "$plist" ] && command -v /usr/libexec/PlistBuddy &> /dev/null; then
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$plist" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$plist" >/dev/null 2>&1 || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$plist" >/dev/null 2>&1 || true
    fi

    rm -rf "$icon_build_dir"
    status "Иконка установлена"
}

generate_and_install_icns "$APP_BUNDLE" "$SCRIPT_DIR/assets/icon.svg"

xattr -cr "$APP_BUNDLE" 2>/dev/null || true
status ".app готов: $APP_BUNDLE"

create_pretty_dmg() {
    local dmg_final="$1"
    local app_bundle="$2"
    local volume_name="$3"
    local bg_png="$4"

    local dmg_temp_dir="$BUILD_DIR/dmg_temp"
    local dmg_rw="$BUILD_DIR/${APP_NAME}-rw.dmg"
    local dmg_mount=""

    rm -rf "$dmg_temp_dir"
    mkdir -p "$dmg_temp_dir"

    cp -r "$app_bundle" "$dmg_temp_dir/"
    if command -v osascript &> /dev/null; then
        rm -f "$dmg_temp_dir/Applications" 2>/dev/null || true
        osascript <<EOF >/dev/null 2>&1 || ln -s /Applications "$dmg_temp_dir/Applications"
tell application "Finder"
    set targetFolder to POSIX file "$dmg_temp_dir" as alias
    set appFolder to POSIX file "/Applications" as alias
    try
        set existing to file "Applications" of targetFolder
        delete existing
    end try
    set a to make new alias file to appFolder at targetFolder
    set name of a to "Applications"
end tell
EOF
    else
        ln -s /Applications "$dmg_temp_dir/Applications"
    fi

    if [ -f "$bg_png" ]; then
        mkdir -p "$dmg_temp_dir/.background"
        cp "$bg_png" "$dmg_temp_dir/.background/background.png"
    fi

    rm -f "$dmg_rw" "$dmg_final"
    : >"$DMG_LOG"
    hdiutil create -volname "$volume_name" -srcfolder "$dmg_temp_dir" -ov -format UDRW "$dmg_rw" >>"$DMG_LOG" 2>&1

    local attach_out
    attach_out="$(hdiutil attach -readwrite -noverify -nobrowse "$dmg_rw" 2>>"$DMG_LOG" || true)"
    local dmg_dev
    dmg_dev="$(echo "$attach_out" | awk 'NR==1{print $1}')"
    dmg_mount="$(echo "$attach_out" | awk 'END{print $3}')"
    if [ -z "$dmg_mount" ]; then
        tail_log "$DMG_LOG" 160
        error "Не удалось смонтировать DMG"
    fi

    osascript <<EOF
tell application "Finder"
    tell disk "$volume_name"
        open
        delay 0.8
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 800, 600}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 12

        try
            set background picture of viewOptions to file ".background:background.png"
        end try

        set position of item "$APP_NAME.app" of container window to {180, 260}
        set position of item "Applications" of container window to {420, 260}

        close
        open
        update without registering applications
        delay 1.2
    end tell
end tell
EOF

    sync
    sleep 0.6

    local detach_target="$dmg_mount"
    if [ -n "${dmg_dev:-}" ]; then
        detach_target="$dmg_dev"
    fi

    local detached=0
    for attempt in 1 2 3 4 5; do
        if hdiutil detach "$detach_target" -quiet >>"$DMG_LOG" 2>&1; then
            detached=1
            break
        fi
        hdiutil detach "$detach_target" -force -quiet >>"$DMG_LOG" 2>&1 || true
        sleep "$attempt"
    done
    if [ "$detached" -ne 1 ]; then
        tail_log "$DMG_LOG" 200
        error "Не удалось отмонтировать DMG"
    fi

    local converted=0
    for attempt in 1 2 3 4 5; do
        rm -f "$dmg_final"
        if hdiutil convert "$dmg_rw" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg_final" >>"$DMG_LOG" 2>&1; then
            converted=1
            break
        fi
        sleep "$attempt"
    done
    if [ "$converted" -ne 1 ]; then
        tail_log "$DMG_LOG" 200
        error "Не удалось собрать DMG (см. лог: $DMG_LOG)"
    fi
    rm -f "$dmg_rw"
    rm -rf "$dmg_temp_dir"
}

echo ""
echo -e "${BLUE}[3/3]${NC} DMG..."

if command -v hdiutil &> /dev/null; then
    DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
    if command -v osascript &> /dev/null; then
        create_pretty_dmg "$DMG_PATH" "$APP_BUNDLE" "$APP_NAME" "$SCRIPT_DIR/assets/dmg/background.png"
    else
        DMG_TEMP="$BUILD_DIR/dmg_temp"
        mkdir -p "$DMG_TEMP"
        cp -r "$APP_BUNDLE" "$DMG_TEMP/"
        ln -s /Applications "$DMG_TEMP/Applications"
        : >"$DMG_LOG"
        hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH" >>"$DMG_LOG" 2>&1 || {
            tail_log "$DMG_LOG" 200
            error "Не удалось собрать DMG (см. лог: $DMG_LOG)"
        }
        rm -rf "$DMG_TEMP"
    fi
    status "DMG: $DMG_PATH"
else
    warn "hdiutil не найден — DMG не создан"
fi

echo ""
echo -e "${GREEN}Готово.${NC}"

