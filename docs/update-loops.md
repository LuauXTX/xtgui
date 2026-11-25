# Empty-window loop and update lifecycle

The reported application called `gui.createApp({title="My App"})`, then
`app:run()` without mounting content. `Application.new` requests initial layout
and style work, but the old flush loop consumed those flags only inside its
`if self.root ...` branch. No root meant no layout, no cleared flags, and 100
passes with no work. The error therefore did not prove a reactive cycle. It also
occurred with the correct dot-style factory call.

Flush now consumes its current layout/style work before entering the layout
engine. The layout engine accepts an empty tree, and the visual-tree refresh
clears stale hit-test/portal entries. New invalidations during layout or its
callbacks remain scheduled for the next pass. Removing the last root follows
the same path. Neither the 100-pass limit nor the 1,000-job scheduler limit was
increased or suppressed.

## Effects, refs and unchanged work

Component hooks remain attached to the same keyed component node. Reconciliation
reuses state/computed/ref/effect objects and disposes them on unmount.

An owned effect runs after mounting layout, after its tracked state/computed
dependencies invalidate, or when its component's props change. A rerender with
unchanged props does not restart it merely because the callback closure was
allocated again. Its callback is refreshed on commit, so future dependency
changes use the latest committed closure. Put reactive reads **inside** the
effect; values only read outside it are not dependencies of that effect.

Owned effects queue on their application and run after reconciliation/layout in
`app:flush()` or the next native frame. Prop/dependency triggers coalesce. Cleanup
runs before a rerun and on unmount. Standalone effects retain synchronous
scheduler behavior. Effects that intentionally converge through several state
updates still run until settled; a non-converging feedback cycle still errors.

`state:set` retains its existing equality semantics: the same scalar/reference
does not notify; allocating another table is a state change. There is no implicit
deep comparison of arbitrary user state. Identical imperative `setProps` patches
and repeated same-size resize requests no longer schedule work. A same-value
patch still clears a corresponding animation override. Stable function refs
attach once and detach on replacement/unmount, rather than reattaching on every
commit.

Portal anchoring may arrange a node multiple times within one layout. `onLayout`
now observes one final bounds change relative to the start of that layout.
Provisional positions no longer cause repeated identical callbacks. Genuine
layout changes continue to notify and may schedule a following pass.

## Diagnostics

`app.diagnostics.flushPasses` and `invalidationCount` describe the last flush.
`recentInvalidations` retains at most 24 causal records for that flush. A loop
error includes up to eight frequent sources, using component/node IDs, hook
numbers, effect source locations when available, and causal state/layout labels.

`app.diagnostics.lastUpdateLoop` retains the last failed flush as:

```luau
{pass=100, phase="effects", sources={{reason="...", count=100}}, recent={"..."}}
```

It stores at most 64 source counters and 24 recent records. These are labels and
counts, not serialized state values. Diagnostic ownership references are weak;
retaining a state value or stop function does not keep an application alive just
for tracing. Standalone scheduler loop errors identify the queued job/effect and
its causal chain too. Diagnostics do not alter the pass limits or hide errors.

To investigate a real loop, find the leading component/hook or `onLayout` node,
then check the state/property it writes. An effect that reads and always changes
the same state, or a layout handler alternating dimensions, is a real feedback
cycle. Make the operation converge; don't increase the guard.

## Regression checks

`tests/update-loops.luau` covers empty trees, root removal, retained state, effect
dependency/props scheduling and cleanup, post-layout effects, same-value updates,
stable refs, unchanged portal bounds, converging updates, and diagnostic reports
for genuine effect/layout loops.

`tests/native-update-loops.luau` runs both an empty window and a stateful/effect
window for three completed GPU frames. The full `tests/run.py --gui` suite also
checks existing widgets, examples and unavailable-adapter cleanup. On Windows,
44 CPU tests and these GPU checks passed using the native LuauXTX executable.
Linux/macOS hosted runs remain separate CI evidence.

`tests/project-smoke.py --runtime /path/to/luauxtx --project /path/to/project`
verifies an actual installed consumer without editing its source. A temporary
driver beside the entrypoint preserves real relative/package resolution. It adds
only a test frame observer/closer and executes the unchanged entrypoint as a
script for three completed frames; it does not wrap an event loop inside the
runtime's synchronous require boundary. The driver is removed afterward. Normal
applications do not close automatically.
