"""Write Finder layout directly so desktop window managers cannot override it."""
from pathlib import Path
import sys

from ds_store import DSStore
from mac_alias import Alias, Bookmark

root = Path(sys.argv[1])
background = root / ".background" / "installer.png"
assert background.is_file() and (root / "MultiCodexPets.app").is_dir()
assert (root / "Applications").is_symlink()
with DSStore.open(str(root / ".DS_Store"), "w+") as store:
    store["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowToolbar": False, "ShowSidebar": False,
        "ShowTabView": False, "ContainerShowSidebar": False,
        "ShowPathbar": False, "PreviewPaneVisibility": False, "SidebarWidth": 180,
        "WindowBounds": "{{200, 120}, {720, 482}}",
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 2,
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "backgroundImageAlias": Alias.for_file(str(background)).to_bytes(),
        "iconSize": 112.0, "textSize": 13.0, "arrangeBy": "none",
        "showIconPreview": True, "showItemInfo": False, "labelOnBottom": True,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    }
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["."]["pBBk"] = Bookmark.for_file(str(background))
    store["MultiCodexPets.app"]["Iloc"] = (185, 240)
    store["Applications"]["Iloc"] = (535, 240)
    for hidden_item in (".background", ".fseventsd"):
        store[hidden_item]["Iloc"] = (2000, 2000)
with DSStore.open(str(root / ".DS_Store"), "r") as store:
    assert store["."]["icvp"]["backgroundType"] == 2
    assert store["."]["bwsp"]["WindowBounds"] == "{{200, 120}, {720, 482}}"
    assert store["Applications"]["Iloc"] == (535, 240)
