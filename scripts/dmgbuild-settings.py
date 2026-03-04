"""DMG layout settings for dmgbuild.

Invoke via release.sh or manually:
    dmgbuild -s scripts/dmgbuild-settings.py \
        -D app_path=dist/Jot.app \
        -D icon_size=128 \
        "Jot" dist/Jot-1.0.0.dmg

Builds the .DS_Store and alias records programmatically — no
Finder or AppleScript involved — so the result is deterministic
and immune to macOS Tahoe's symlink-icon rendering bugs.
"""

import os

app_path = defines.get("app_path")  # noqa: F821  (injected by dmgbuild)
app_name = os.path.basename(app_path)
background_path = defines.get("background", "")
icon_sz = int(defines.get("icon_size", "128"))

files = [app_path]
symlinks = {"Applications": "/Applications"}

icon_locations = {
    app_name: (180, 230),
    "Applications": (500, 230),
}

icon_size = icon_sz
text_size = 14
window_rect = ((120, 120), (900, 620))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
format = "UDZO"

if background_path:
    background = background_path
