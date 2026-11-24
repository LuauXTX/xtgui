"""Install committed XTGUI using a temporary registry and native bare-name imports.

Local Git fixtures are explicitly opted in; no registry publication or user config writes.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from run import ROOT, execute, runtime_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--xtpkg", type=Path, default=ROOT.parent / "xtpkg")
    args = parser.parse_args()
    runtime = runtime_path(args.runtime)
    with tempfile.TemporaryDirectory(prefix="xtgui package ") as temporary:
        base = Path(temporary)
        env = os.environ.copy()
        registry = base / "registry"
        env.update(XTPKG_REGISTRY=str(registry), XTPKG_CACHE_DIR=str(base / "cache"),
                   XTPKG_CONFIG_HOME=str(base / "config"), XTPKG_GLOBAL_DIR=str(base / "global"),
                   GIT_TERMINAL_PROMPT="0")
        source = base / "source"
        execute(["git", "-c", "core.hooksPath=", "clone", "--local", "--no-hardlinks", ROOT, source], base, env)
        cli = [runtime, args.xtpkg.resolve() / "src/main.luau"]
        execute([*cli, "publish", "--dry-run"], source, env)
        execute([*cli, "publish", "--output", "xtgui-submission.json"], source, env)
        metadata = json.loads((source / "xtgui-submission.json").read_text(encoding="utf-8"))
        # Point only this private fixture registry at the isolated local Git checkout.
        version = next(iter(metadata["versions"]))
        metadata["versions"][version]["source"]["url"] = str(source)
        (registry / "packages").mkdir(parents=True)
        (registry / "packages/xtgui.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        (registry / "index.json").write_text(json.dumps({"registry_version": 1, "packages": {
            "xtgui": {"path": "packages/xtgui.json", "description": metadata["description"]}
        }}, indent=2), encoding="utf-8")
        project = base / "consumer"
        project.mkdir()
        execute([*cli, "init", "--no-git"], project, env)
        execute([*cli, "add", "xtgui", "--allow-local-sources"], project, env)
        script = project / "consumer.luau"
        script.write_text('''local gui=require("xtgui")
local direct=require("./packages/xtgui/src/init")
local wrapper=require("./packages/xtgui")
assert(gui==direct and gui==wrapper,"Package import aliases split framework state")
local count=gui.state(1)
local app=gui.createApp()
app:render(function(ui)return ui:Text({id="text",text=tostring(count:get())})end)
count:set(2);app:flush();assert(app:find("text").props.text=="2")
app:destroy();count:dispose()
print("Native bare-name XTGUI consumer passed")
''', encoding="utf-8")
        execute([runtime, script], project, env)
        execute([*cli, "install", "--frozen", "--offline", "--allow-local-sources"], project, env)
        execute([*cli, "add", "xtgui", "--global", "--allow-local-sources"], project, env)
        assert (base / "global/packages/xtgui/src/init.luau").is_file()
        assert not (base / "global/bin/xtgui.cmd").exists()
        assert not (base / "global/bin/xtgui").exists()
        execute([*cli, "remove", "xtgui", "--global", "--allow-local-sources"], project, env)
        assert not (base / "global/packages/xtgui").exists()
    print("XTGUI package integration passed: registry add, canonical import aliases, frozen/offline install, global library and cleanup")


if __name__ == "__main__":
    main()
