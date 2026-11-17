# Companion Pets — concept 1

Editable native source: `CompanionPets-v1.icon`.

This approved design is the app's installed icon. The two original
mascot artwork layers were generated for this project; no user pet artwork or
service logos are used. Their source PNGs retain transparent backgrounds.

The background, platform mask, appearance variants, and rendering are handled
by Apple's Icon Composer. The smaller mint dog is a foreground group; the ivory
cat is the second group behind it. Both layers have independent positions and
scales in the document.

Validated with Icon Composer 2.0 (121), supplied by Xcode 27.0:

- macOS Default, Dark, and TintedDark, at 1024 × 1024
- macOS Default, at 64 × 64

The rendered files are in `Previews/`. The PNGs are previews; the `.icon` package
is the editable source compiled by `script/build_and_run.sh` using Apple's `actool`.
The app bundles the resulting `Assets.car` and `.icns` fallback, with matching
`CFBundleIconName` and `CFBundleIconFile` metadata.

Open the `.icon` package with Icon Composer. To render the default preview again
from the repository root:

```bash
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Design/AppIcon/CompanionPets-v1.icon --export-image \
  --output-file Design/AppIcon/Previews/companions-v1-default.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

References:

- [Apple Icon Composer](https://developer.apple.com/icon-composer/)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

Apple's official empty icon template and Landmarks sample were consulted for the
native document format. None of the sample's artwork is included here.
