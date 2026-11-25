# Public API

The package exports a typed public surface for Luau analysis: `gui.App`,
`gui.AppOptions`, `gui.State<T>`, `gui.Element`, `gui.Props`, and `gui.Style`.
Additional component contracts are exported from `src/Types.luau`. Constructors,
callbacks and state values retain their types through ordinary package imports;
the language server does not need package-specific completion rules.
Custom data-view item records and user-defined theme tokens remain dynamic;
annotate item callbacks for application-specific record fields.

## Applications

`gui.createApp(options)` creates a retained tree/resource owner. Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `title` | `"XTGUI"` | Native window title. |
| `width`, `height` | `800`, `600` | Positive logical viewport dimensions, at most 16384. |
| `theme` | global default (`"dark"`) | `"light"`, `"dark"`, or an inherited definition. |
| `resizable`, `visible`, `vsync` | `true` | Native window options. Hidden windows may receive no frames. |
| `fontFiles` | none | Family -> path, or family -> weight -> path. |
| `clipboard` | session clipboard | Synchronous `{get=function()->string, set=function(text)}` provider. |
| `captureSensitivity` | `1` | Raw device-unit -> logical movement multiplier during locked capture. |
| `onReady(app)` | none | First native frame, after the native window is ready. |
| `onFrame(dt, app)` | none | After a completed frame; synchronous. |
| `onResize(event, app)` | none | Logical resize/scale notification. |
| `onClose(app)` | none | Return false to cancel an OS close request. |
| `onError(message, app)` | none | Report a callback failure. See error handling below. |

Methods:

| Method | Behavior |
| --- | --- |
| `render(fnOrDescriptor)` | Mount/update content; `fn` receives `gui`. Returns app. |
| `run()` | Run this window and destroy its tree/resources on exit. Only one native run per process. |
| `gui.run({app1, app2})` | Run multiple windows in one native event loop. |
| `flush()` | Synchronously reconcile queued changes and calculate layout. Does not submit a GPU frame. |
| `find(id)` | Find the first concrete host element with `props.id`. |
| `setTheme(theme)` | Change this application's theme. |
| `resize(width, height)` | Request an OS size and invalidate logical layout. Confirmation is asynchronous. |
| `invalidate(element?)` | Request paint, optionally invalidating one element's cached commands. |
| `shortcut(chord, fn)` | Register a shortcut; returns unregister function. Return false to permit normal handling. |
| `after(seconds, fn)` | Schedule a synchronous callback; returns a logical cancellation function. Cancelled on close. |
| `loadFont(pathOrNil, size)` | Borrow a cached native font for Canvas drawing. |
| `loadImage(path)` | Borrow a cached native image. |
| `getSemantics()` | Snapshot semantic roles, labels, state, focus and transformed bounds. |
| `close()` | Force native closure; bypasses `onClose`. |
| `destroy()` | Idempotently unmount, cancel work and release resources. |

Borrowed fonts/images are owned across live XTGUI applications. Do not dispose
them independently. The last application releases shared native caches. Raw gfx
aliases share that native lifetime too. Paths are relative to `process.cwd()`.
Recreate applications after changing assets; hot resource replacement is not an
automatic watcher.

Native callbacks must return synchronously. Start asynchronous work using
`require("@luauxtx/async/task").spawn(...)`; call `:await()` inside the task.
Check that an app/element is still alive before applying its eventual result.
The text editor demonstrates this pattern.

Preparation errors throw without committing the proposed tree. Failed callback
operations are reported through `onError`, or close the app and throw from `run`.
Errors during an active native frame close the window even with `onError`, so an
unbalanced/invalid frame cannot persist. Cleanup continues after individual
cleanup failures and reports them after releasing resources. User callback side
effects and external I/O cannot be rolled back by reconciliation.

## Elements and common properties

All concrete components accept `id`, sibling `key`, `children` (except leaf
components), `style`, layout/style properties, `theme`, `disabled`, `ref`,
`onMount(element)`, `onUnmount(element)`, and
`onLayout(bounds, element, previousBounds)`. Refs are `{current=elementOrNil}` or
callbacks receiving the element/nil. Mount/effect callbacks see committed layout.

`gui.ref(initial?)` is stable inside a component. `gui.onCleanup(fn)` registers
component-lifetime teardown. `gui.useApp()` and `gui.useViewport()` work during a
component render. Viewport reads subscribe that component to confirmed logical
size changes.

An element has stable `id` (framework serial), `props.id` (developer name),
`key`, `parent`, `children`, `alive`, `box`, `renderCount` and `app`.
Prefer methods over mutating internal fields:

* `setProps(patch)` merges properties, clears matching animation overrides and queues update.
* `destroy()` unmounts it; a later parent declarative render can recreate it.
* `getBounds()` returns `{x,y,width,height}` in untransformed logical coordinates.
* `getChildren()`, `find(id)`, `findKey(key)` inspect descendants.
* `focus()`, `capturePointer()`, `releasePointer()` manage interaction.
* `scrollTo(x,y)` scrolls a ScrollView, clamped to measured content.

Imperative property patches are staged and validated at flush; rejected patches
leave committed props/animation state intact. Keys cannot be changed by setProps.
A subsequent parent declarative render can replace an imperative property value.

Functional component props are passed through unchanged, including State objects.
Construct concrete host elements to apply styles and handlers. Forward refs to
the intended concrete host. Hooks cannot change order/count between renders.

## Basic components

| Component | Properties and behavior |
| --- | --- |
| `Text` | `text` string/number; `wrap=true`; font/color/alignment styles. No children. |
| `Button` | `text`, children, `onClick(event,element)`, `onActivate(event,element)`; Enter/Space activation. |
| `IconButton` | Button with `icon` or `text`, square default size. Supply an `ariaLabel`. |
| `TextInput` | `value`, `defaultValue`, `onChange(text,element)`, `placeholder`, `readOnly`, `password`, `maxLength`, `onSubmit(text,element)`. Single line. |
| `TextArea` | TextInput properties plus multiline editing, `wrap=true`, `acceptTab=false`. |
| `Checkbox` | `checked`, `defaultChecked`, `text`, `onChange(bool,element)`. |
| `RadioButton` | Checkbox properties plus `group`; mutually exclusive activation and arrow navigation. |
| `Switch` | Checkbox behavior with a switch presentation. |
| `Slider` | `min=0`, `max=100`, `step` optional, `value`, `defaultValue`, `onChange(number,element)`; drag/arrows/Home/End. |
| `ProgressBar` | `min=0`, `max=1`, `value`, `defaultValue`; display only. |
| `Image` | Required PNG/JPEG `source` path, `fit="contain"` or default stretch, optional RGB(A)/hex `tint`, `alt`. No children. |
| `Separator` | Colored 1px intrinsic separator; set width/height for orientation. |

Input values and checked/value controls accept direct State bindings. A plain
controlled value remains the owner's responsibility; `onChange` reports a
requested value. Uncontrolled default values apply only at mount. Slider values
are clamped to min/max for user input and painting. Disabled ancestors disable
their descendants and block input through their bounds.

## Layout components

`Row`, `Column`, `Container` (column default), `Stack`, `Grid`, `Spacer` and
`ScrollView` accept the shared styles described in the layout guide. `Spacer`
defaults to `flexGrow=1`. `ScrollView` adds `onScroll({x,y,viewportWidth,viewportHeight},element)`.
For horizontal scrolling, give content an explicit width greater than its viewport.

`SplitPane` accepts `children={first,second}` or `first`/`second`,
`direction="horizontal"` (default) or `"vertical"`, `ratio`/`defaultRatio=0.5`,
`onChange(ratio)`, `minFirst`, `minSecond` in logical pixels, `handleSize=6`,
`keyboardStep=10`, `height=260`, width and `disabled`. Its separator supports
pointer dragging and arrow-key resizing.

## Composite components

Composite controlled properties also accept State bindings, with `onChange(value)`.

| Component | Properties |
| --- | --- |
| `Select` / `Dropdown` | `items`/`options` array of strings/numbers or `{label,value,key?,disabled?}`; `value/defaultValue`, `onChange`, `placeholder`, `width=220`, `maxHeight=240`, `disabled`. Arrows, Enter, Escape, Home/End and single-character option search. |
| `Tabs` | `tabs={{key,label,content or children,disabled?}}`, `value/defaultValue`, `onChange`, `keepAlive=false`, width/height/gap. Arrow/Home/End header navigation. Inactive content unmounts unless keepAlive. |
| `Accordion` | `items={{key,label,content or children,disabled?}}`, `value/defaultValue`, `onChange`, `multiple=false`, `contentPadding=8`. Value is one key/false, or a key -> bool map in multiple mode. |
| `Modal` | `open/defaultOpen`, `onChange`, `onDismiss`, `dismissible=true`, `title`/`ariaLabel`, `children`, width=440, optional height/y/padding/gap, backdropColor/zIndex. Overlay, focus trap/restore, outside/Escape dismissal. Title is a semantic label; add a Text child for a visible heading. |
| `Popover` | `open/defaultOpen`, `onChange`, `onDismiss`, optional `trigger` descriptor or `anchor` ref/element, `children`, width=260, x/y, zIndex, `trapFocus=false`, triggerWidth/triggerHeight. |
| `Tooltip` | Wrap `children`; `text`, `delay=0.5`, width=220, fontSize=13, disabled. Appears on hover/focus, cancels on leave/blur/unmount; non-interactive. |
| `ContextMenu` | Wrap `children`; `items={{label,value,disabled?,onSelect(value)}}`, optional `onSelect(value)`, width=200. Right-click, menu focus, arrows and Escape. |

Portals escape ancestor clipping/transforms and are clamped to the viewport.
Default layers: popovers/selects 1000, context menus 1500, modal 2000, tooltip 3000.
Nested portal layers are relative to their containing portal, so a select inside
a modal stays above it. Anchors use transformed screen bounds.
Overlay panels belong to their logical event ancestry. A popup height larger than
the viewport can extend beyond it; use an inner ScrollView and sensible maxHeight.

## Virtualized data views

`ListView` accepts `items`, `itemKey(item,index)`, `renderItem(item,index,selected)`,
`rowHeight=32`, `height=240`, `width`, `overscan=3`, `itemPadding`,
`value/defaultValue` (selected key), `onChange(key)`, `onSelect(item,index)`,
`onActivate(item,index)`, `onScroll`, `onLayout`, `onKeyDown(event,key,index)` and
semantic `role/itemRole/ariaLabel`. Default item keys are `item.key` or array
indices. Supply stable unique keys for changing/reordered data. Row heights are
fixed; variable-height virtualization is not implemented. Arrows, Home/End and
PageUp/PageDown select and reveal rows. Enter activates. Rows unmount outside the
overscan window; keep durable row state in the item model.

`Table` uses ListView for its body. Properties: `items`, `columns`, `itemKey`,
`rowHeight=32`, `height=300`, `headerHeight=34`, width, `value/defaultValue`,
`onChange`, `onActivate`, `sortable`, `onSort(columnKey)`. Columns are
`{key,label,width?,grow?,sortable?,render(value,item,index,selected)?}`. A column
with no fixed width shares remaining width by grow weight (default 1). Clicking
sortable headers toggles ascending/descending order; column resize/drag is not
implemented.

`TreeView` accepts `items={{key,label,children}}`, optional `itemKey` and
`getChildren`, `expanded/defaultExpanded` key -> bool map, `onExpandedChange(map)`,
`value/defaultValue`, `onChange(key)`, rowHeight=30, height=260, indent=18 and width.
It flattens expanded nodes into a virtualized list. Left/Right collapse, expand or
navigate parent/first child. Keys must be unique; visible cycles/depth overflow
produce errors. Expansion state remains in the model while rows recycle.

## Canvas

```luau
local font = app:loadFont(nil, 16)
gui.Canvas({width=240, height=100, onPaint=function(frame, bounds, element)
    frame:rect({x=bounds.x, y=bounds.y, width=240, height=100,
        radius=8, color={30,50,80}})
    frame:text({x=bounds.x+12, y=bounds.y+12, text="Custom paint",
        font=font, color={255,255,255}})
end})
```

The scoped frame exposes native `rect`, `line`, `text`, `image`, `pushClip`,
`popClip`, `pushTransform`, `popTransform` and `deltaTime`. Coordinates are absolute
within the current element/ancestor transform; bounds are untransformed logical
coordinates. Canvas clips to its bounds. Its private stacks are restored after
the callback; underflow/errors are reported. It cannot clear or finish the native
frame. Do not retain the frame or yield inside `onPaint`. Canvas colors are native
RGB(A) values; caller-specified alpha is used for custom commands. Use
`app:invalidate()` for external changes not represented by reactive state.

## Animation

`gui.tween(element, properties, options)` returns a tween with `cancel()`,
`status` (`running`, `completed`, `cancelled`) and `element`. Supported properties:
`opacity`, `x`, `y`, `width`, `height`, `radius`, `borderWidth`, `background`,
`color`, `borderColor`, and numeric transform fields. Dimensions must be numeric
when animated. Colors interpolate channels, and transforms interpolate supplied
fields. `x/y` offset normal flow; `transform.x/y` translate without layout changes.

Options: `duration=0.3`, `delay=0`, `easing="easeOutCubic"` or function,
`["repeat"]=0` (extra cycles, -1 infinite), `reverse=false` (forward/back cycle),
`onUpdate(amount,tween)`, `onComplete(tween)`, `onCancel(tween)`. Easing names:
linear, easeInQuad, easeOutQuad, easeInOutQuad, easeInCubic, easeOutCubic,
easeInOutCubic, easeOutSine, easeInOutSine.

Tweens sample current values when their delay expires. A new active tween that
touches the same element/property cancels the older tween. Cancellation freezes
the current override. Overrides take precedence over declarative styles until
replaced by a tween or cleared with `element:setProps({property=value})`.

```luau
local timeline = gui.timeline()
    :to(element, {opacity=0.4}, {duration=0.2})
    :wait(0.1)
    :parallel({
        {element=element, properties={x=80}, options={duration=0.3}},
        {element=other, properties={opacity=1}, options={duration=0.3}},
    })
    :play({onComplete=function() print("Done") end})
```

`to(..., atSeconds?)` can overlap steps explicitly. Timelines play once; cancel
the timeline to cancel its tweens. Infinite child tweens are rejected. A host
`transition={duration=0.15, easing="easeOutQuad", properties={"background","opacity"}}`
animates interactive style changes; default transition properties are background,
color, borderColor and opacity. Active animation advances from monotonic time.
