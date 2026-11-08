# GodoSprite (Pixel plugin)

A pixel art + animation editor that lives inside the Godot editor. It adds a new **Pixel** tab next to
*2D*, *3D*, *Script* and *AssetLib* in Godot, giving you an Aseprite-style workflow without leaving the
engine.

![Pixel tab](https://img.shields.io/badge/engine-Godot%204.7.2-478cbf)

## Features

- **Pixel tab in the editor** with an always-visible dark canvas, left tool sidebar, top action bar and a
  bottom animation timeline.
- **Sprites are edited at their real size** — a 32×32 image is 32×32 pixels on screen. Newly loaded frames
  are zoomed to fill 75% of the canvas.
- **Drag-and-drop sprites** from Godot's FileSystem dock (or from your OS) onto the canvas.
- **Animation workflow** — drop *several* images at once (same size) and they become an animation,
  Aseprite-style:
  - Frame strip with thumbnails, click to switch frames.
  - Drag-and-drop reordering of frames.
  - Per-frame duration in ms (with live FPS display).
  - Play / Pause, looping playback, Space toggles, `,` `.` / `←` `→` step frames with wraparound.
  - Onion skinning: previous frame tinted red, next frame tinted blue.
  - New frame / Duplicate frame / Delete frame / move left / move right.
- **Tools**: Select, Move, Draw (brush), Erase, Fill (flood), Square, Circle, Line, Eyedropper.
  Pixel-snapped, one-pixel cursor with a white outline so you always know which pixel you are editing.
- **Selection + clipboard**: drag a rectangular selection; Ctrl+C / Ctrl+V copies and pastes selected
  pixels anywhere; selections live on a hidden floating layer that merges back automatically.
- **Color palette**: right-click a swatch to save the current color, left-click to select it.
  The palette is saved to disk and restored when the editor restarts.
- **Non-destructive save flow**: edits live in memory until you press **Redraw**, which writes every frame
  back to its source file. Before writing, Redraw stores the previous file in
  `addons/pixel/rollback/` (mirroring the project path), letting you press **Rollback** to restore the
  pre-redraw image. Rollback files are hidden from the editor with a `.gdignore` so they can't be
  accidentally imported or moved around.
- **Undo / Redo** frame-aware snapshot history (buttons or keyboard).
- The **Rollback** button reverts the currently displayed frame's file to its pre-redraw backup.

## Keyboard shortcuts (with canvas focused)

| Key | Action |
| --- | --- |
| `Z` | Undo |
| `U` | Redo |
| `B` | Brush (Draw) |
| `E` | Erase |
| `M` | Select |
| `F` | Fill |
| `I` | Eyedropper |
| `O` / `P` | Circle |
| `K` | Line |
| `D` | Duplicate frame |
| `N` | New frame |
| `Space` | Play / Pause |
| `,` or `←` | Previous frame (wraps around) |
| `.` or `→` | Next frame (wraps around) |
| `Ctrl+C` / `⌘C` | Copy selection |
| `Ctrl+V` / `⌘V` | Paste at cursor |

## Top bar buttons

| Button | Purpose |
| --- | --- |
| **Redraw** | Saves **all frames** to their source files (new frames get `name_001.png`-style names) and creates rollback backups |
| **Discard** | Reloads the animation from disk, throwing away unsaved edits (unsaved editor-created frames survive) |
| **Undo / Redo** | Frame-aware editing history |
| **Rollback** | Restores the current frame's pre-redraw backup |

## Installation

1. Make sure your project uses **Godot 4.7.x** (`config/features` includes `"4.7"`).
2. Copy the `addons/pixel/` folder into your project:
   ```
   your-project/
     addons/
       pixel/
         plugin.cfg
         plugin.gd
         plugin.gd.uid
         pixel_canvas.gd
         pixel_canvas.gd.uid
     project.godot
   ```
3. Open your project in Godot and go to *Project → Project Settings → Plugins* and **enable** "Pixel",

4. A new **Pixel** button appears in the editor's top-right main-screen switcher (next to *Script*) with
   a rounded-square icon. Click it; the tab opens automatically when the project is opened.

No other dependencies are needed — it is pure GDScript using only built-in engine APIs.

## Notes & tips

- Dropping **one** image edits that image; dropping **two or more same-size images** creates an animation.
  Frames dropped must match the first frame's size; mismatched files are skipped (see the Output panel).
- Frames that come from *New Frame* or *Duplicate* have no file yet — pressing **Redraw** names them
  automatically (`spr_001.png`, `spr_002.png` … next to the first frame's sprite) and saves them.
- Drawing is limited to an active selection, so you can protect areas while painting.
- The Move tool pans the view when you click outside a selection.
- Rollback backups of files outside the project are stored under a hash folder so they never collide.

## License

MIT — do whatever you like, no warranty.
