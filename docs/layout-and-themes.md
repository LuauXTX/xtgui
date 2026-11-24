# Layout, styles and themes

## Logical layout

All dimensions use logical pixels, with origin at the top-left and positive Y
downward. OS display scaling belongs to gfx. Width/height/min/max/basis and
absolute anchors accept nonnegative numbers, `"NN%"`, or `"auto"`/nil. Percentages
refer to the parent's available content box. Padding/margin are nonnegative
numbers or CSS-order arrays `{top,right,bottom,left}` (`{vertical,horizontal}` is
also accepted), or a table with named sides. Cyclic auto/percentage CSS semantics
are not attempted: measurement uses the available ancestor viewport constraints.

```luau
gui.Row({padding=16, gap=12, height=240, children={
    gui.Column({width=180, children={gui.Text({text="Sidebar"})}}),
    gui.Column({flexGrow=1, minWidth=120, children={gui.Text({text="Body"})}}),
}})
```

Row/Column/Container distribute their main axis by `flexBasis` (or measured size),
`flexGrow=0`, `flexShrink=1`, min/max limits and margins. Constrained items freeze
while free space redistributes, with bounded passes. `alignItems="stretch"`
controls the cross axis; `alignSelf` overrides it. Supported alignment: start,
center, end, stretch. `justifyContent`: start, center, end, space-between,
space-around, space-evenly. `gap`, `rowGap`, `columnGap` control spacing.

Unspecified cross dimensions stretch; explicit cross dimensions remain fixed.
Root content fills the viewport unless explicit dimensions constrain it.
Functional components have transparent layout wrappers which delegate their
concrete root's dimensions, flex properties and margins. A root descriptor can
return nil or false to render nothing. Children arrays can contain false values
for conditional content; use dense arrays (nil holes terminate array traversal).

Stack layers children, stretching unspecified dimensions. Siblings paint/hit-test
by `zIndex`, then child order. Absolute children are excluded from normal flow:

```luau
gui.Container({height=160, children={
    gui.Text({text="Body"}),
    gui.Button({position="absolute", right=12, bottom=12,
        width=100, height=36, text="Action"}),
}})
```

For relative flow, `x/y` offset a box after placement. For transforms, use
`transform={x=10,y=10,rotation=0.1,scaleX=1,scaleY=1}`. Rotation is clockwise in
radians around the element's top-left. Transforms compose with ancestors; hit
testing uses the inverse world transform. Zero-scale elements do not receive hits.

## Grid

```luau
gui.Grid({columns={120,"1fr","2fr"}, rows={"auto","1fr"}, gap=8, height=240,
    children={
        gui.Text({text="Label"}),
        gui.Container({columnSpan=2, children={gui.Text({text="Spanning content"})}}),
        gui.Container({gridRow=2, gridColumn=2, rowSpan=1,
            children={gui.Text({text="Explicit cell"})}}),
    },
})
```

`columns=3` is shorthand for three equal fractional tracks. An array supports
fixed pixel numbers, percentages, `"auto"`, and `"Nfr"`. Rows default to measured
auto heights; provide a rows array for fixed/fractional rows. Placement uses
1-based gridRow/gridColumn, columnSpan/rowSpan. Automatic placement avoids occupied
cells; explicit placement may overlap deliberately. Tracks do not implement CSS
minmax/repeat functions. Child min/max constraints are supported.

## Scrolling and clipping

Give ScrollView a bounded viewport height. Its children keep their natural main
sizes rather than shrinking into the viewport. Wheel lines map to 36 logical
pixels; pixel deltas stay logical. Shift exchanges horizontal/vertical scrolling.
Nested wheel events bubble to an outer scroller when the inner one cannot move.

```luau
local scrollRef=gui.ref(nil)
gui.ScrollView({ref=scrollRef, height=220, children={
    gui.Container({width=800, children={gui.Text({text="Wide content",wrap=false})}}),
}})
-- In an event/effect after mount:
scrollRef.current:scrollTo(100,0)
```

`overflow="hidden"` clips descendants of any container. Clip rectangles transform
with their owner, nest as convex intersections in the native backend, and constrain
hit testing. Corner radius affects backgrounds/strokes, not child clip shape.
Scrollbars are not a separate draggable widget in this release; scrolling works
through wheel/trackpad, focus reveal, keyboard data views and `scrollTo`.

ListView/Table/TreeView virtualize fixed-height rows instead of mounting all data.
Their content extents determine scroll limits. Resizing recalculates visible rows.
Use unique stable item keys and store durable editing state outside recycled rows.

## Style precedence

From lowest to highest:

1. Theme defaults and inherited font/color.
2. Component defaults and `theme.components.ComponentName`.
3. `style` object or left-to-right array of reusable styles.
4. Direct style properties on the host descriptor.
5. `hoverStyle`, `activeStyle`, `focusedStyle`, `disabledStyle` (in that order),
   or the corresponding `style.hover/active/focused/disabled` object.
6. Active/persisted animation overrides.

Disabled presentation multiplies opacity by 0.45. Ancestor opacity multiplies
standard widget draw colors. Canvas custom commands use their supplied native
alpha, so apply custom alpha in the callback when needed.

Properties include background/color/borderColor, borderWidth, radius, opacity,
fontSize/fontFamily/fontWeight/fontPath, lineHeight, textAlign (`start/center/end`),
verticalAlign (`center`), zIndex, cursor, overflow, display (`flex/none`), transform,
shadow and all layout properties. `shadow={x=0,y=4,blur=12,color="#00000050"}` draws
bounded translucent layers, not a Gaussian blur. Colors accept RGB(A) arrays,
#RGB/#RGBA/#RRGGBB/#RRGGBBAA, common names, or theme color tokens like `$primary`.

```luau
local action=gui.style({background="$primary",radius=8,padding={8,16}})
gui.Button({style={action,{fontSize=18}}, text="Save",
    hoverStyle={background="#2563EB"}, transition={duration=0.15}})
```

`gui.setTheme(definition)` changes the default for subsequently created apps.
`app:setTheme(definition)` changes a live application. A host `theme={...}` merges
with its ancestor theme. Missing tokens fall back through that inheritance.
Built-in themes are `"light"` and `"dark"`.

```luau
gui.setTheme({
    colors={primary="#3B82F6",background="#111827",surface="#1F2937",text="#F9FAFB"},
    radius=8,spacing=8,
    components={Button={height=38}},
})
```

The theme's spacing token is available for application definitions; concrete
layout padding/gaps remain explicit. Text inherits font size/family/weight and
color. The native API selects system sans-serif at weight 400 by default. It
does not expose family/weight selection by name; map font files explicitly:

```luau
local app=gui.createApp({fontFiles={
    UI={[400]="assets/Regular.ttf",[700]="assets/Bold.ttf"},
}})
gui.Text({text="Heading",fontFamily="UI",fontWeight=700,fontSize=24})
```

Alternatively use `fontPath`. Requested unmapped non-default families/weights
produce clear errors rather than pretending to render bold. Native Unicode font
fallback remains available. Quarter-pixel font sizes share cached resources.
