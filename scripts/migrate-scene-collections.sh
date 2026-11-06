#!/usr/bin/env bash
# Switch old filters in your OBS scene collections to the engine filter, "Silly Effect".
#
# This plugin opens filters saved by obs-shaderfilter ("shader_filter"),
# obs-retro-effects ("obs_retro_effects_filter") and Shadertastic
# ("shadertastic_filter") on its own: it converts their settings when OBS loads
# them, and OBS saves the converted settings when it closes. You do not need
# this script for that.
#
# This script then changes the ID of each converted filter to "silly_effect",
# so the collection no longer depends on the old IDs.
#
#   1. Install the plugin. Start OBS once with each collection, then close OBS.
#   2. Run this script. It keeps a backup of each changed collection.
#
# Filters that OBS has not converted yet are left alone; the script says how many.
set -euo pipefail

SCENES="${XDG_CONFIG_HOME:-$HOME/.config}/obs-studio/basic/scenes"

if pgrep -x obs >/dev/null; then
	echo "OBS is running. Close OBS, then run this script again." >&2
	exit 1
fi

shopt -s nullglob
for f in "$SCENES"/*.json; do
	python3 - "$f" <<'EOF'
import json, shutil, sys

path = sys.argv[1]
old_ids = {"shader_filter", "obs_retro_effects_filter", "shadertastic_filter"}
data = json.load(open(path))
changed = waiting = 0
for src in data.get("sources", []):
    for flt in src.get("filters", []) or []:
        if flt.get("id") not in old_ids:
            continue
        if "effect" in (flt.get("settings") or {}):
            flt["id"] = "silly_effect"
            flt["versioned_id"] = "silly_effect"
            changed += 1
        else:
            waiting += 1
name = path.rsplit("/", 1)[-1]
if changed:
    backup = path + ".pre-silly-effect"
    shutil.copy2(path, backup)
    with open(path, "w") as out:
        json.dump(data, out, indent=4, ensure_ascii=False)
    print(f"{name}: switched {changed} filters to silly_effect (backup: {backup.rsplit('/', 1)[-1]})")
if waiting:
    print(f"{name}: {waiting} filters are not converted yet. Open this collection in OBS once, close OBS, and run the script again.")
EOF
done
