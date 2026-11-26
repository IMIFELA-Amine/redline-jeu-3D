# Xogot Modeler for Godot (beta)

Polygon modeling for `MeshInstance3D`, inside the Godot 4.7 editor on Linux
and Windows: vertex, edge and face editing, shape recipes, UVs, painting and
export. It is the Modeler from [Xogot](https://xogot.com), as a Godot
add-on.

## This is a beta

Each beta build stops working 30 days after it was built. `BUILD.txt`, next
to this file, says when. After that, the editor shows a message and the
Modeler stays off until you install a newer build from
<https://xogot.com/modeler-xplat>. The editor starts warning a week before.

Asset Store releases are marked as beta, with Stable unchecked. Project >
Tools > Xogot Modeler — About / Beta Updates shows your version and expiry
and lets you check for a replacement, even after expiry. New betas appear
in a dismissible notice in the 3D toolbar. Automatic checks run at startup
at most once daily; you can disable them in that dialog. Checks respect
Godot's offline mode and do not require a Xogot account. Checking for updates
does not extend this build's 30-day lifetime.

Scenes you made keep working: the Modeler stores its data in standard
`ArrayMesh` resources, which open with or without the add-on.

## Requirements

- Godot 4.7 or later.
- **Windows:** Windows 10 or later, x86_64. The arm64 build is included but
  has not been tested on arm64 hardware yet.
- **Linux:** x86_64 or arm64, with glibc 2.35 or later (Ubuntu 22.04,
  Debian 12, Fedora 36, or newer).

## Installing

1. Unzip the download at the root of your project, so that
   `addons/xogot_modeler` sits next to `project.godot`.
2. Open the project, and enable **Xogot Modeler** in
   Project › Project Settings › Plugins.

The Linux and Windows downloads unzip into the same folder. If your team
works on both, unzip both, in either order.

The add-on runs only in the editor. Exported games leave it out.

To update, close the editor, delete `addons/xogot_modeler`, and unzip the new
build. To uninstall, disable the plugin and delete `addons/xogot_modeler`.
The combined Asset Store ZIP includes Linux and Windows. Teams using the
separate ZIPs should install both from the same beta version after removing
the old folder. Save your work before closing Godot.

## Using it

Select a `MeshInstance3D` and use the Modeler's controls in the 3D editor's
toolbar:

- **Make Editable** converts a mesh or CSG shape; **Add Mesh** draws a new
  shape, Poly Shape, Bezier Plane or Bezier Block (Alt-click places a shape at
  once).
- **Object / Vertex / Edge / Face** switch the selection mode (H cycles).
- **Actions** lists the commands for the mode. Commands with settings show
  them in a panel at the bottom of the viewport while you adjust them.
- **Paint** applies materials, vertex colours and smoothing groups.
- **Selection & Handles** sets the handle orientation, pivot, rectangle and
  Shift selection, X-ray and soft selection; **Options** has the rest.
- The **Editable Mesh** section of the inspector edits shape recipes, and has
  the UV, collision and export commands.
- The **Mesh UV** bottom panel is the UV editor.

Click an element to select it; drag a selected element, or the gizmo's
handles, to move it. Hold Shift when the drag starts to extrude first.
Right-click the selection for its commands. Shortcuts are under
Editor Settings › Shortcuts › modeler.

Scenes move between this add-on and Xogot in both directions.

## Known issues

- The Modeler is in English only.
- Placing a shape at once (Alt-click) uses the grid point in front of the
  camera, because the stock editor has no API for its orbit point.
- With Use Snap on, a Shift-drag extrusion stays in place until the drag
  passes the first snap step.
- Godot may report leaked objects when the editor quits. They are harmless.

## Reporting problems

Go to <https://xogot.com/modeler-xplat>. Include the contents of `BUILD.txt`
and the editor's Output panel.

## Licence

See `LICENSE.txt` and `THIRD_PARTY_NOTICES.txt`.
