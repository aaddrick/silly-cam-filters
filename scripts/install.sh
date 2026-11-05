#!/usr/bin/env bash
# Build Silly Cam Filters and install it into the system OBS (Fedora layout).
#
#   scripts/install.sh            build + install
#   scripts/install.sh --no-build install the existing build/
#
# If the standalone plugins obs-shaderfilter, shadertastic or obs-retro-effects
# are installed, this script moves them to a backup folder first. They register
# the same filter IDs, so OBS cannot load them next to this plugin.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME=silly-cam-filters
PREFIX=/usr
LIBDIR=lib64
PLUGIN_DIR="$PREFIX/$LIBDIR/obs-plugins"
DATA_DIR="$PREFIX/share/obs/obs-plugins"
BACKUP="${XDG_DATA_HOME:-$HOME/.local/share}/$NAME/replaced-plugins-$(date +%Y%m%d-%H%M%S)"

if pgrep -x obs >/dev/null; then
	echo "OBS is running. Close OBS, then run this script again." >&2
	exit 1
fi

if [[ "${1:-}" != "--no-build" ]]; then
	cmake -S "$ROOT" -B "$ROOT/build" -G Ninja \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_INSTALL_LIBDIR="$LIBDIR" \
		-DFETCHCONTENT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$NAME/deps"
	cmake --build "$ROOT/build" -j"$(nproc)"
fi

# Move the old standalone plugins out of the way.
old=(
	"$PLUGIN_DIR/obs-shaderfilter.so" "$DATA_DIR/obs-shaderfilter"
	"$PLUGIN_DIR/shadertastic.so" "$PLUGIN_DIR/shadertastic" "$DATA_DIR/shadertastic"
	"$PLUGIN_DIR/obs-retro-effects.so" "$DATA_DIR/obs-retro-effects"
	# Older cmake installs put the plugins here; Fedora OBS never loads them.
	"$PREFIX/lib/obs-plugins/obs-shaderfilter.so"
	"$PREFIX/lib/obs-plugins/shadertastic.so"
	"$PREFIX/lib/obs-plugins/obs-retro-effects.so"
)
for path in "${old[@]}"; do
	if [[ -e "$path" ]]; then
		mkdir -p "$BACKUP$(dirname "$path")"
		echo "Moving $path to $BACKUP$path"
		sudo mv "$path" "$BACKUP$path"
	fi
done

# Remove the previous install of this plugin, so deleted data files go away.
sudo rm -rf "$DATA_DIR/$NAME"
sudo cmake --install "$ROOT/build"

# CMake does not always rewrite the runpath; set it explicitly.
sudo patchelf --set-rpath '$ORIGIN/'"$NAME" "$PLUGIN_DIR/$NAME.so"

echo
echo "Installed:"
ls -la "$PLUGIN_DIR/$NAME.so" "$PLUGIN_DIR/$NAME/"
if ldd "$PLUGIN_DIR/$NAME.so" | grep -q 'not found'; then
	echo "Missing libraries:" >&2
	ldd "$PLUGIN_DIR/$NAME.so" | grep 'not found' >&2
	exit 1
fi
echo "All libraries found."
if [[ -d "$BACKUP" ]]; then
	echo "Old plugins are in $BACKUP"
	echo "Run scripts/migrate-scene-collections.sh before you start OBS."
fi
