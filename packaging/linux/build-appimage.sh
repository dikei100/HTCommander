#!/bin/bash
# Build HTCommander-X AppImage for Linux
# Usage: ./build-appimage.sh [Release|Debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="${1:-Release}"
APPDIR="$ROOT_DIR/packaging/linux/AppDir"
OUTPUT_DIR="$ROOT_DIR/releases"

echo "=== Building HTCommander-X AppImage ==="
echo "Configuration: $CONFIG"

# Clean and build
echo "Building HTCommander.Desktop..."
dotnet publish "$ROOT_DIR/HTCommander.Desktop/HTCommander.Desktop.csproj" \
    -c "$CONFIG" \
    -r linux-x64 \
    --self-contained true \
    -p:PublishSingleFile=false \
    -p:PublishTrimmed=false \
    -o "$APPDIR/usr/bin"

# Create AppDir structure
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/metainfo"

# Copy desktop file
cp "$SCRIPT_DIR/HTCommander.desktop" "$APPDIR/usr/share/applications/"
cp "$SCRIPT_DIR/HTCommander.desktop" "$APPDIR/"

# Copy icon (use the project icon, convert if needed)
if [ -f "$ROOT_DIR/assets/HTCommander.ico" ]; then
    # Try to extract PNG from ICO using ImageMagick if available
    if command -v convert &> /dev/null; then
        convert "$ROOT_DIR/assets/HTCommander.ico[0]" -resize 256x256 \
            "$APPDIR/usr/share/icons/hicolor/256x256/apps/htcommander.png"
        cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/htcommander.png" "$APPDIR/htcommander.png"
        cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/htcommander.png" "$APPDIR/.DirIcon"
    else
        echo "WARNING: ImageMagick not found, skipping icon conversion"
    fi
fi

# Create AppRun
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/HTCommander.Desktop" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# Download appimagetool if not present
APPIMAGETOOL="$SCRIPT_DIR/appimagetool-x86_64.AppImage"
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool..."
    wget -q "$APPIMAGETOOL_URL" -O "$APPIMAGETOOL"
    echo "$APPIMAGETOOL_SHA256  $APPIMAGETOOL" | sha256sum -c - || { echo "ERROR: appimagetool checksum verification failed!"; rm -f "$APPIMAGETOOL"; exit 1; }
    chmod +x "$APPIMAGETOOL"
fi

# Build AppImage
mkdir -p "$OUTPUT_DIR"
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUTPUT_DIR/HTCommander-X-x86_64.AppImage"

echo ""
echo "=== AppImage built successfully ==="
echo "Output: $OUTPUT_DIR/HTCommander-X-x86_64.AppImage"

# Cleanup
rm -rf "$APPDIR"
