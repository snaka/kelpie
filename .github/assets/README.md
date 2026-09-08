# README assets

Images referenced by the repository `README.md`. Kept here rather than under
`Sources/` so that renaming or regenerating the app's icon set never breaks the
README.

| File | What it shows |
|---|---|
| `icon.png` | Copy of the generated 256 px app icon (`Sources/Kelpie/Assets.xcassets/AppIcon.appiconset/icon_256.png`). Refresh it whenever `scripts/make-icon.swift` output changes. |
| `menubar.png` | The menu bar item with the blocked, working and done segments all present. |
| `popover.png` | The popover listing agents grouped into BLOCKED / WORKING / DONE / IDLE. |

## Capture conventions

- Shoot on a Retina display and leave the capture at its native size — the
  README sets a `width` attribute at half that, so the image stays sharp.
- Use the same appearance (light or dark) for every screenshot in one set.
- `Cmd+Shift+4` then Space captures a window with its shadow; drag a region
  instead for the menu bar so the shot stays tight around the item.
