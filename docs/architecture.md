# Architecture, performance and limits

## Data flow

`src/init.luau` exposes descriptors, state/hooks, built-in components and application
creation. There is no native initialization during module require.

1. Components render descriptors under dependency tracking and hook scopes.
2. Reconciler prepares a candidate plan, validates props/resources/keys and only
   then commits it to retained elements. Keyed children keep IDs, local state,
   input state and resources across reorder. Rejected plans dispose new hooks and
   restore staged computed callbacks. A non-interactive layout mirror validates
   actual parent constraints before destructive unmounts. Its metadata nodes are
   reused between preparations; it never calls component renders or lifecycle
   handlers. This adds a validation layout pass, with shared measurement caches,
   in exchange for retaining the old tree on constraint/grid failures.
3. Scheduler batches subscriptions/effects; affected components or State-valued
   host bindings enter the app's update set. Ancestor updates cover descendants.
4. Layout resolves themes/styles, measures constrained content, and arranges flex,
   grid, stack, absolute and scroll geometry. Transparent component wrappers
   delegate concrete layout properties. Layout/measurement caches persist in
   unaffected branches.
5. VisualTree derives affine transforms, polygon clips, paint order and hit-test
   ancestry. Portals form window-level overlay layers.
6. Paint retains per-element draw commands. Renderer walks visible content and
   submits native primitives, balanced clips/transforms, text, images and scoped
   Canvas callbacks during that window's onFrame.

Gfx owns winit/wgpu, surface recovery and DPI rasterization. XTGUI creates windows
with `continuous=false`, requests redraw on changes, and drains ordered events.
No reactivity polling loop runs between frames. Focused text caret blinking and
active animations/timers schedule explicit asynchronous wakeups.

## Ownership and teardown

Apps own trees, timers, animation registrations and input state. Component hooks
own their local state, computed subscriptions and effect cleanups. Unmount detaches
observers before disposing state, cancels element tweens/capture/focus, clears refs
and runs lifecycle cleanup. Apps may be destroyed during a multi-window run.

Native fonts/images are shared cache aliases. Disposing a native alias invalidates
other aliases, so XTGUI keeps a process-wide resource cache and releases it only
when the last app is destroyed. This is intentional: destroying one app cannot
invalidate another app's font. Borrowed Canvas resources must not be manually
disposed. Native windows/surfaces are closed per app. Repeated destroy is safe.
Cleanup errors are aggregated after the remaining cleanup runs.

Native task.delay has no cancellation API. XTGUI timers use cancellation flags
and at most 50ms delay chunks so closing an app does not leave a long timer keeping
the process alive. Timers do not force GPU frames until their callback changes UI.
These are scheduler wakeups, not a spinning event loop.

## Caching and diagnostics

`app.diagnostics` contains frames/layouts/updates counts, latest layoutTime and
preflightTime in seconds, preflightNodes, dirtyRegions/lastDirtyRegions, and latest
paint `{nodes,commands,cached}`.
Elements expose renderCount for finding expensive rerender paths. Profile custom
components using monotonic `os.clock()` around application-specific work.

* Reconciliation avoids rerunning unaffected sibling components.
* Measurement caches use available constraints; unchanged arranged branches skip
  arrangement work.
* Text layout caches up to 1024 runs, wraps by measured fitting spans, and lazily
  caches caret-prefix widths. Font/image GPU caches are reused by native gfx.
* Retained paint commands are reused until props/styles/layout/input invalidate
  them. Opacity is applied on submission.
* Geometry outside the viewport is culled; clipped primitives use native clipping.
* ListView/Table/TreeView mount only visible fixed-height rows plus overscan.

Dirty regions are diagnostics/invalidation bounds, not GPU scissor-only repaint.
The native backend clears every new frame and does not retain the previous
framebuffer. XTGUI therefore submits all visible content on a requested redraw.
Native gfx batches GPU work internally. A backend retained framebuffer API would
be needed for genuine partial GPU repaint.

Keep render functions pure and cheap. Use computed values for derived data, State
bindings for controls, batch related changes, stable keys and immutable item
arrays. Do not hold per-row durable state only in virtualized row components.
For many distinct font sizes, normalize typography instead of exhausting native
resource limits. Window creation is event-driven; do not repeatedly call run.

## Boundaries and limits

* Desktop only; a compatible native runtime/display/GPU is required. Module load
  and CPU font measurement can work without a GPU; run failures are catchable and
  destroy resources. Browser/mobile hosts are not supported.
* One gfx.run per process, up to the backend's 16 live windows. Use gui.run for
  multiple apps. Native callbacks cannot yield or retain frame handles.
* Backend limits include 64 live fonts, 256 images, 64-depth native clip/transform
  stacks, 100000 draws / 1000000 vertices per frame, 64 KiB text runs, 8192px
  rasterized dimensions, bounded image/font files and GPU texture memory. Extremely
  deep transformed UI can reach native stack limits before the tree depth limit.
* Framework reconciliation limits depth to 128 and planned nodes to 100000. Grid
  placement/tracks are bounded. Reactive jobs/layout passes have explicit loop
  guards. Text editing snapshots and layout caches are bounded.
* Layout is a deterministic subset, not CSS/Yoga. No flex wrapping, negative
  margins, CSS minmax/repeat, variable-height virtualization, rich text or arbitrary
  path rendering. Data-view rows have fixed height. ScrollView has wheel/focus/API
  scrolling, without a separate draggable scrollbar widget.
* Child clips are rectangular; rotated rectangles become polygon intersections.
  Rounded backgrounds do not create rounded child masks. Shadows are translucent
  layers rather than Gaussian blur. No filters or CSS effects are implied.
* Native font-name/weight selection is unavailable. Use explicit font file mappings.
  Default system sans-serif is weight 400. No fonts/images are bundled or fetched.
* Clipboard is process-local unless a host provider is supplied. Native OS
  clipboard and native accessibility APIs are missing. Framework semantics are
  exposed, with no screen-reader claim.
* Editing segments common Unicode grapheme forms and converts IME byte offsets,
  but lacks complete UAX #29 and visual bidirectional caret navigation. It targets
  small UTF-8 documents. Actual OS IME behavior needs platform/input-method testing.
* Paint errors close the active window safely. Atomic preparation protects the old
  retained tree against invalid proposed renders; it cannot roll back arbitrary
  callback side effects, user I/O or mutate-in-place application tables.

The code stays inside this package; LuauXTX remains a low-level graphics/runtime
provider. Third-party components can use the same public hooks, descriptors,
events, styles and Canvas primitives without modifying Rust.
