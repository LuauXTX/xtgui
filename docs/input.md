# Events, focus, text and clipboard

## Event propagation

Handlers on concrete host elements receive `(event, element)`. Matching capture
handlers add `Capture`: `onClickCapture`, `onKeyDownCapture`, etc. Capture travels
from outermost host to target; bubbling travels back. Functional component wrappers
are transparent. `event.target`, `currentTarget`, `phase`, `app`, `type`,
`defaultPrevented` and `propagationStopped` identify dispatch state.

Methods: `preventDefault()`, `stopPropagation()`, `capturePointer()`,
`releasePointer()`. Stopping propagation does not itself cancel default behavior.
Default actions run after handlers. Disabled controls block events through their
bounds. `pointerEvents="none"` skips an entire subtree for hit testing.

| Handler | Fields/behavior |
| --- | --- |
| `onMouseMove` | Window `x/y`, target-local `localX/localY`, movement `deltaX/deltaY`. |
| `onMouseDown`, `onMouseUp` | `button` (left/right/middle/etc), coordinates. |
| `onClick`, `onDoubleClick` | Primary button release on the pressed element; double interval 0.4s. |
| `onMouseEnter`, `onMouseLeave` | Non-bubbling path notifications, enter outer-to-inner, leave inner-to-outer. |
| `onDragStart`, `onDrag`, `onDragEnd` | Starts after 3px movement; `totalX/totalY` from press plus per-move deltas. |
| `onPointerCancel` | Capture/press cancelled by loss of focus/unmount. |
| `onWheel` | `scrollX/scrollY`, `unit` (lines/pixels), pointer coordinates. Prevent default to consume. |
| `onContextMenu` | Right-button request; context menu components prevent native/default handling. |
| `onKeyDown`, `onKeyUp` | `key`, physical `code` when native, `modifiers`, `repeat` (use `["repeat"]` in Luau). |
| `onTextInput` | Unicode `text`, `ime=true` for committed composition. |
| `onFocus`, `onBlur` | Logical focus with `relatedTarget`; bubbles for focus-aware containers. |

Mouse events preserve native input order. Rendering never polls keyboard state.
The onEvent notification drains the backend's queue so inputs cannot accumulate
unconsumed between frames. Scroll events try the nearest ScrollView and then its
ancestors. Drawing/hit testing share sibling stacking, world transforms and clips.
Overlays render in portal layers and retain logical event ancestry.

Native pointer capture requests locked mode with a confined fallback. XTGUI also
maintains logical capture if the OS denies the request. Locked capture uses raw
device deltas with `captureSensitivity`; these are device units, not DPI-scaled
mouse coordinates. Capture is released on focus loss, close and unmount. Draggable
elements (`draggable=true`), sliders and text selection use it. Programmatic test
events deliberately use logical capture without grabbing the OS mouse.

## Keyboard navigation

Button, IconButton, text inputs, toggles and sliders are focusable by default.
Any host can use `focusable=true`. `tabIndex=0` participates in document order;
positive values sort before zero; negative values permit programmatic focus
without a Tab stop. `focusable=false` disables focus entirely.

Tab/Shift+Tab move focus, showing visible focus outlines. Radio groups provide one
Tab stop and arrow selection. Buttons accept Enter/Space; sliders accept arrows,
Home/End. List/tree/table selection handles arrows and page navigation. Focused
items are revealed by ancestor scrollers. Modal/menu traps constrain traversal and
restore the previous focus on dismissal. No trap permits focusing hidden or
disabled descendants.

```luau
local unregister=app:shortcut("mod+s",function(event)
    saveDocument()
end)
```

Chords accept ctrl/control, cmd/meta/super, alt, shift, or mod (Control or Super
according to the incoming modifier state). Examples: `"ctrl+shift+p"`, `"mod+s"`,
`"alt+ArrowLeft"`. Call the returned function on teardown for registrations made
outside a component. Components can register in an effect and return unregister.
Capture/bubble key handlers can prevent shortcut/default handling.

## Text editing

TextInput is single-line. TextArea supports multiline insertion, optional wrapping
and `acceptTab=true` for literal tabs. Enter and Tab are inserted through key
handling; duplicate control characters from ordinary textInput are filtered.
IME commits are inserted as committed Unicode text.

Supported operations:

* Left/Right, Shift selection, word navigation with Control/Super/Alt.
* Home/End for the visual line, Control/Super+Home/End for the document.
* Up/Down and PageUp/PageDown with a retained horizontal target in multiline text.
* Backspace/Delete, word deletion, selection replacement, double-click word selection.
* Control/Super+A/C/X/V, Z, Shift+Z, and Y for selection/clipboard/undo/redo.
* Mouse drag selection, horizontal and vertical caret scrolling.
* `readOnly`, optional `maxLength` in cluster units, and password masking.

Editing indices are zero-based grapheme boundaries. UTF-8 byte offsets are used
only at the native IME boundary, then converted. The segmenter groups combining
marks in common ranges, variation selectors, emoji modifiers, ZWJ sequences,
regional pairs and CRLF. It is not a complete UAX #29 implementation. Navigation
is logical; full bidirectional caret movement and all Indic/complex-script cluster
rules need a richer segmentation/glyph-position API. Native text rendering itself
uses the backend's shaping and font fallback. Prefix widths are measured lazily
for caret hit testing rather than measuring every text prefix at each edit.

Undo/redo retains up to 100 edit snapshots. There is no time-based edit grouping.
Controlled external replacement resets edit history; a control's own State-bound
edit keeps it. `maxLength` limits insertion, while the native 64 KiB text limit is
also enforced. Text areas are intended for small documents, not multi-megabyte IDE
buffers. Password values are excluded from semantics and copy/cut shortcuts;
application code still owns the actual value and should avoid logging it.

## Clipboard and IME limits

Native gfx exposes composition and candidate positioning, but **no operating
system clipboard**. XTGUI's default clipboard is shared within the current
process. It supports copy/cut/paste between XTGUI controls without shell commands.
An embedding host may supply a synchronous provider:

```luau
local app=gui.createApp({clipboard={
    get=function() return hostClipboard.read() end,
    set=function(text) hostClipboard.write(text) end,
}})
```

`hostClipboard` above is an application-owned integration, not an XTGUI/global
builtin. Reads must return valid UTF-8 strings. XTGUI does not invoke external
clipboard commands. Native read/write clipboard functions would be needed for a
portable default OS clipboard implementation.

Focused editable controls enable native IME and position its candidate region at
the logical caret transformed into the window. Preedit is temporary, shown with
an underline, and committed through textInput. Blur/IME disable clears preedit.
Actual IME availability and candidate UI depend on the OS/window system. Tests
exercise composition events through the production dispatcher; the validation
record distinguishes this from manual testing of each OS input method.

## Framework accessibility

`app:getSemantics()` returns an application tree with semantic roles, stable IDs,
labels, focusability/focus, disabled/selected/expanded/checked state, values and
transformed bounds. Controls provide default roles; `role`, `ariaLabel`, `alt`,
`ariaHidden`, `level` and related data-view properties refine it.

This tree supports application automation and future adapters. Native gfx has no
Windows UI Automation, macOS AX or Linux AT-SPI bridge. The semantics tree and
keyboard navigation do **not** establish compatibility with screen readers.
