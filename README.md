# XTGUI

XTGUI is a retained, reactive desktop GUI library for LuauXTX. Components, layout,
editing, focus, events, themes, animation and virtualization are implemented in
Luau. Native `@luauxtx/gfx` supplies windows, input, GPU primitives and shaped text.
XTGUI adds no Rust dependencies or runtime modifications.

## Requirements and installation

Use the native desktop LuauXTX runtime with `@luauxtx/gfx`, event-driven windows,
native package imports and async tasks. The tested runtime source revision is
`f42d4926cbd305fe9bc13c4b538e39d806ae5f66` in
[LuauXTX](https://github.com/MINTILER-DEV/LuauXTX).
Windows, Linux and macOS follow that backend's desktop/GPU support; browser/mobile
hosts are unsupported. A window-system session and compatible GPU/software adapter
are needed to open windows. Linux additionally needs the runtime's keyboard/window
libraries (on Debian/Ubuntu: `libxkbcommon0`, `libxkbcommon-x11-0`).

Once this version has been reviewed and published in the XTPKG registry:

```sh
xtpkg add xtgui
luauxtx app.luau
```

Before registry publication, install this checkout into another project:

```powershell
xtpkg add path:D:/GitHub/Repositories/xtgui
```

```sh
xtpkg add path:/path/to/xtgui
```

Both use the same package entrypoint and native `require("xtgui")` import. XTGUI is
a library with no executable bin or install hooks. It has no runtime package
dependencies; XTest is only a test dependency. Committing this repository does not
publish its registry version. See [package validation](docs/validation.md).

## Hello World

```luau
local gui = require("xtgui")
local app = gui.createApp({
    title = "My Application", width = 900, height = 600,
    theme = "dark", resizable = true,
})
local count = gui.state(0)

app:render(function(ui)
    return ui:Column({padding=24, gap=12, children={
        ui:Text({text="Hello from XTGUI!", fontSize=28}),
        ui:Button({
            text="Clicked " .. count:get() .. " times",
            onClick=function() count:update(function(old) return old+1 end) end,
        }),
    }})
end)
app:run()
count:dispose()
```

`gui.Column(props)` and `ui:Column(props)` are equivalent. Descriptors are retained
and reconciled; a new descriptor does not imply a new element. Use sibling `key`
values when lists reorder. Requiring XTGUI never opens a window. `render()` performs
CPU reconciliation/layout; `run()` owns the native event loop until windows close.

## Components and state

```luau
local Counter = gui.component(function(props)
    local count = gui.state(0)
    local doubled = gui.computed(function() return count:get()*2 end)
    gui.effect(function()
        print("Count changed:", count:get())
        return function() print("Effect cleanup") end
    end)
    return gui.Column({children={
        gui.Text({text=props.title .. ": " .. doubled:get()}),
        gui.Button({text="Increment", onClick=function() count:set(count:get()+1) end}),
    }})
end, "Counter")
```

Hook calls must keep the same order and count in a component. Local state persists
across keyed rerenders and is disposed on unmount. Render functions must be pure;
use effects, `onMount`, or event callbacks for side effects. Effects track reads,
run after committed layout, clean up before rerunning, and clean up on unmount.
Only components and host bindings that read a changed value are invalidated.

`state:get()`, `set(value)`, `update(fn)`, `subscribe(fn)` and `dispose()` are
available. A subscription returns an unsubscribe function. Computed values are
lazy, cached and dependency-tracked. `gui.batch(fn)` coalesces notifications;
updates are painted together in the next requested frame. Detached/headless tests
can call `app:flush()` explicitly. Cycles/update loops and writes during render
produce errors.

Host properties accept State objects directly:

```luau
local text, checked = gui.state(""), gui.state(false)
gui.TextInput({value=text, placeholder="Name"})
gui.Checkbox({checked=checked, text="Enabled"})
```

These controls write their State bindings automatically. Plain `value`/`checked`
properties are controlled: update them through your callback. Omit them and use
`defaultValue`/`defaultChecked` for internal state. Replace data arrays/tables when
changing them; in-place mutations do not notify observers. Forward component
callbacks and refs to host elements explicitly; component props are not an extra
event target. See [API and component reference](docs/api.md).

## Layout, styling and input

Rows and columns support grow/shrink/basis, alignment, justification, gaps,
padding/margins, percentages and min/max sizes. Grids support numeric, percentage,
`auto` and fractional tracks, explicit placement and spans. Stack layers children;
absolute children use `left/right/top/bottom` or `x/y`. Coordinates are logical
pixels, independent of display scale. ScrollView clips content and supports wheel
and programmatic scrolling. See [layout and themes](docs/layout-and-themes.md).

Themes include light/dark defaults, inherited tokens and custom component styles.
Styles include colors, borders, rounded backgrounds, opacity, transforms, shadow
approximations, font mappings and interactive variants. Font weights/families
require explicit font files when the native system-default face is insufficient.

Events capture then bubble through host elements. Handlers can prevent default
behavior, stop propagation and capture the pointer. Keyboard navigation includes
Tab/Shift+Tab, radio arrows, control-specific arrows, shortcuts and modal trapping.
Text editing supports Unicode clusters, selection, multiline/word navigation,
undo/redo, scrolling and native IME preedit/commit. See
[events, text and clipboard](docs/input.md).

```luau
gui.tween(app:find("panel"), {opacity=0, x=200}, {
    duration=0.3, easing="easeOutCubic",
})
```

Tweens support delay, repeat, reverse, cancellation and completion. Timelines
sequence or overlap them. Hover transitions use the same engine. Windows are
event-driven; unfocused static interfaces do not request periodic redraws.

## Examples

From this repository:

```sh
luauxtx examples/hello.luau
luauxtx examples/calculator.luau
luauxtx examples/settings.luau
luauxtx examples/editor.luau
luauxtx examples/gallery.luau
```

The gallery includes custom drawing, clipped scrolling, dropdowns, modals,
popovers, tooltips, context menus, a resizable split pane, a tree and a sortable
10,000-row virtualized table. The calculator accepts keyboard input. The editor
opens/saves UTF-8 files asynchronously and prompts before discarding changes.
Settings are applied to the example session; it does not write user configuration.
Add `--smoke` for automatic exercise/close with error assertions.

## Testing and limits

```sh
python tests/run.py --runtime /path/to/native/luauxtx --xtpkg ../xtpkg --gui --package
```

For offline/private development, add `--xtest ../xtest` to use that explicitly
trusted Git checkout in an isolated test project. No user registry, PATH, global
packages or caches are changed. See [validation and CI](docs/validation.md).

Clipboard defaults to process-local storage; optional synchronous providers can
bridge a host clipboard. Native gfx has no OS clipboard API. `app:getSemantics()`
provides a framework accessibility tree, with password values excluded; the
backend has no native accessibility bridge, so screen-reader support is not
claimed. Child clipping is rectangular; layered shadows approximate blur. Editing
uses common grapheme groups and logical navigation, not complete UAX #29 or
bidirectional caret handling. Backend text/resource/stack limits apply.

Dirty regions, retained paint commands, measurement/layout caches, culling and
virtualization reduce CPU work. Each requested GPU frame still submits all visible
content because native frames clear their surface. See the full
[architecture, performance and limitations](docs/architecture.md).

MIT licensed. No GUI code is added to LuauXTX's native primitive layer.
