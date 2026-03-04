"""DMG layout settings for dmgbuild.

Invoke via release.sh or manually:
    dmgbuild -s scripts/dmgbuild-settings.py \
        -D app_path=dist/Jot.app \
        -D volume_icon=Jot/Resources/AppIcon.icns \
        -D icon_size=128 \
        -D background=Jot/Resources/DMG/background.png \
        -D applications_alias=/path/to/Applications.alias \
        "Jot" dist/Jot-1.0.0.dmg
"""

import os

app_path = defines.get("app_path")  # noqa: F821  (injected by dmgbuild)
app_name = os.path.basename(app_path)
volume_icon_path = defines.get("volume_icon", "")
background_path = defines.get("background", "")
icon_sz = int(defines.get("icon_size", "128"))
applications_alias = defines.get("applications_alias", "")

files = [app_path]
symlinks = {"Applications": "/Applications"}

if applications_alias and os.path.exists(applications_alias):
    files.append((applications_alias, "Applications"))
    symlinks = {}

hide_extensions = [app_name]
hide = []

icon_locations = {
    app_name: (260, 240),
    "Applications": (520, 240),
}

if volume_icon_path and os.path.isfile(volume_icon_path):
    icon = volume_icon_path  # noqa: F841
    hide.append(".VolumeIcon.icns")

if background_path and os.path.isfile(background_path):
    background = background_path  # noqa: F841

icon_size = icon_sz
text_size = 14
window_rect = ((120, 120), (900, 648))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
format = "UDZO"
