#!/usr/bin/env bash
# Point existing OBS scene collections at the shader files in this plugin.
#
# obs-shaderfilter filters store the full path of their shader file, for
# example /usr/share/obs/obs-plugins/obs-shaderfilter/examples/VHS.shader.
# This plugin keeps those files in .../silly-cam-filters/shaderfilter/.
# The script rewrites the paths in every scene collection and keeps a backup.
# Shadertastic and retro-effects filters store no paths, so they need no change.
set -euo pipefail

SCENES="${XDG_CONFIG_HOME:-$HOME/.config}/obs-studio/basic/scenes"
OLD=/usr/share/obs/obs-plugins/obs-shaderfilter/
NEW=/usr/share/obs/obs-plugins/silly-cam-filters/shaderfilter/

if pgrep -x obs >/dev/null; then
	echo "OBS is running. Close OBS, then run this script again." >&2
	exit 1
fi

shopt -s nullglob
for f in "$SCENES"/*.json; do
	n=$(grep -o "$OLD" "$f" | wc -l)
	[[ "$n" -eq 0 ]] && continue
	backup="$f.pre-silly-cam-filters"
	cp -p "$f" "$backup"
	sed -i "s#$OLD#$NEW#g" "$f"
	echo "$(basename "$f"): changed $n paths (backup: $(basename "$backup"))"
done
