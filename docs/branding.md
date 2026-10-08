# FamilyApp icon

The mark is a soft navy house with two lit windows and a red chimney on a
sunflower-yellow background. It reads as "our home" without lettering or
figures, so the same asset works in the Android launcher, browser and Alice
skill catalogue, and stays legible down to 16 px.

| Role       | Color     |
| ---------- | --------- |
| Background | `#F6C445` |
| House      | `#233656` |
| Chimney    | `#E8553E` |
| Windows    | `#FFF1C9` |

## Assets

- `app/assets/branding/familyapp-icon.svg`: vector source on the 108-unit
  adaptive icon grid.
- `app/assets/branding/familyapp-icon-1024.png`: 1024 x 1024 export for reuse.
- `app/assets/branding/alice-icon-224.png`: opaque RGB PNG, exactly 224 x 224,
  ready to upload in Yandex Dialogs.
- Android API 26+ uses the adaptive icon in `mipmap-anydpi-v26/ic_launcher.xml`:
  the `ic_launcher_background` color, the vector `ic_launcher_foreground` and the
  vector `ic_launcher_monochrome` for themed icons (Android 13+). The artwork
  stays inside the 72-unit circle that launcher masks keep visible.
- Legacy Android launcher PNGs: mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144,
  xxxhdpi 192.
- Web: favicon 32, regular and maskable manifest icons at 192 and 512.

## Regenerating

All of the files above come from the geometry and colors defined in
`app/scripts/export_brand_icons.py`. To change the icon, edit the script and run
`python app/scripts/export_brand_icons.py` with Pillow installed. Exported files
are committed, so Flutter builds do not require Pillow or an icon-generation
package. The background color is also set by hand in
`android/app/src/main/res/values/brand_colors.xml` and `web/manifest.json`.

For the skill, upload `alice-icon-224.png` in the icon field of Yandex Dialogs.
Devices may cache old launcher/browser icons until an app update or
reinstallation.

## Design provenance

Chosen in the interactive icon workbench from several house shapes, accent
details and palettes. The selection was the "soft" house, chimney accent,
"sun" palette, lit windows, scaled to 120%. Earlier generated alternatives,
including the previous forest-green family icon (`forest-family`), are kept in
`app/assets/branding/variants/`.

Adaptive icon implementation reference:
[Android documentation](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).
