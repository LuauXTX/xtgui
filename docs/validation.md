# Validation and development

## Commands

Use a native executable directly (especially when passing shell-sensitive CLI
arguments on Windows):

```sh
python tests/run.py --runtime /path/to/luauxtx --xtpkg ../xtpkg
python tests/run.py --runtime /path/to/luauxtx --xtpkg ../xtpkg --gui --package
```

The runner bootstraps XTest using the committed tests/xtpkg.toml and lockfile into
an isolated cache/config, checks frozen reproduction, and runs the XTest suite.
It does not execute package install hooks. A private mirror can be selected with
XTPKG_REGISTRY. For offline/private source development:

```sh
python tests/run.py --runtime /path/to/luauxtx --xtpkg ../xtpkg --xtest ../xtest --gui --package
```

The explicit XTest checkout is cloned without hooks into a temporary directory.
Current XTGUI source/tests are copied into an isolated suite project with that
path dependency. The committed manifest/lockfile is not rewritten. This is the
real XTest package, not a stand-in assertion API. No user config/registry/PATH or
real global package directory is changed. Git and Python 3.11+ are needed for test
orchestration, not by XTGUI consumers.

`stylua --check src examples tests` checks formatting; `.styluaignore` excludes
installed packages. Use `stylua --verify` when formatting to check AST equivalence.

## Coverage

The update-loop regression run passes 44 CPU tests, including empty-tree flush,
stable state/effect/ref identity, deferred effects, no-op updates, final portal
bounds, preserved dirty work after a failed layout, and actionable bounded
diagnostics for real cycles. Both new native update-loop modes complete three
GPU frames, alongside the existing widget integration and five example checks.
See [the fix and causal diagnostics](update-loops.md).

The XTest suite exercises component identity, keyed reorder, rejected renders,
state/computed dependency changes, batched subscriptions, effect/state disposal,
hook lifetime, custom component props/refs, nested flex and grid, percentages,
transformed hit testing, stacking and capture/bubble order, cancellation,
keyboard focus/radios/hidden/disabled controls, Unicode/clipboard/undo/IME events,
scroll virtualization, overlays/focus traps, data views, split panes, timelines,
themes, semantics/password privacy and cleanup failures.

With `--gui`, new native processes run:

* Real GPU frames for reactive clicks, shaped text, clipped scrolling and resize.
* Images from a generated PNG, custom Canvas, nested clips/transforms, dropdowns,
  modal focus, ListView/Table/TreeView, animation and multi-window resource lifetime.
* Automatic smoke exercises of hello, calculator, settings, editor and gallery.
* An impossible adapter request, asserting catchable initialization failure and
  resource cleanup.

Interaction assertions inject events through the production framework dispatcher.
They exercise real widget/default behavior but do not claim physical keyboard,
mouse-driver, OS clipboard or every native IME has been automated. Native gfx has
its own Rust module/window/pixel tests in the runtime repository; no Rust was
modified by XTGUI. Screenshots can be taken from the running gallery for manual
visual review; generated images belong under ignored local/, not the package.

## XTPKG integration and release

`--package` tests the committed HEAD. Commit intended changes first. It clones a
clean local Git checkout, validates `publish --dry-run`, prepares submission JSON,
creates a temporary registry using that exact source/integrity, then exercises:

* `xtpkg add xtgui --allow-local-sources` against the isolated fixture registry.
* Native `require("xtgui")` and direct/wrapper imports sharing one module identity.
* State/rendering behavior from installed package files.
* Frozen/offline reproduction.
* Global library installation/removal with no executable entrypoint or launcher.

`--allow-local-sources` is only for that private fixture; it is not needed for a
normal approved HTTPS registry package. This test never publishes metadata or
pushes source. Publish dry-run validates a clean committed tree, supported UTF-8
package contents, license, entrypoint, metadata and integrity.

To release after review, commit the complete tree, push the referenced commit to
the manifest's HTTPS repository, generate an `xtgui-0.1.0-submission.json` with
`xtpkg publish --output ...`, and submit it to the official registry's submissions/
inbox. Registry workflows/maintainers validate and approve the metadata. Preserve
existing immutable versions. Only then is ordinary `xtpkg add xtgui` available
from that registry. Preparing JSON or passing a local fixture is not publication.

## Platform record

Local validation was performed on Windows with the native runtime revision
documented in README: XTest plus the real GPU tests/examples above. The component
gallery was also visually inspected in a real window. Linux/macOS checks are
defined in `.github/workflows/test.yml`; their presence is not evidence that
hosted runs have passed. WSL on the development machine cannot start its VM, so
no local Linux result is claimed. OS IME, OS clipboard providers, screen readers,
hardware/device diversity, long soaks and physical-input automation remain outside
the local validation record.

The workflow builds the pinned runtime, obtains pinned XTPKG/XTest sources and
runs CPU/package checks on Windows/Linux/macOS. Linux graphics use Xvfb and Mesa;
Windows graphics run in its desktop runner. macOS runs CPU/package checks because
hosted-session Metal/window availability is not assumed. Repositories that are
private require a read-only cross-repository `XTGUI_DEPENDENCIES_TOKEN` secret for
checkout; default GITHUB_TOKEN only covers this repository. This is distinct from
runtime package installation, which never acquires credentials or changes Git
security configuration.
