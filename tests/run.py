"""Run XTest, optional real GPU windows/examples, and isolated package integration.

No administrator privileges, global installs or real user configuration changes.
Each graphics test gets a new process because gfx.run is single-use.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def execute(command, cwd=ROOT, env=None, timeout=120):
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, text=True,
                            encoding="utf-8", errors="replace", capture_output=True,
                            timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}\n"
                           + result.stdout + result.stderr)
    if result.stdout.strip():
        print(result.stdout.strip(), flush=True)
    return result.stdout


def runtime_path(value):
    if not value:
        raise RuntimeError("Pass --runtime /path/to/native/luauxtx")
    if Path(value).suffix.lower() in {".cmd", ".bat"}:
        value = execute([value, ROOT / "tests/runtime-probe.luau"]).strip()
    resolved = Path(value).resolve()
    if not resolved.is_file():
        raise RuntimeError(f"Native runtime not found: {resolved}")
    return resolved


def png_fixture(path):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    pixels = b"".join(b"\0" + bytes([40, 120, 240, 255]) * 16 for _ in range(16))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", default=shutil.which("luauxtx"))
    parser.add_argument("--xtpkg", type=Path, default=ROOT.parent / "xtpkg")
    parser.add_argument("--xtest", type=Path, help="Use an explicit trusted XTest Git checkout for offline/private development")
    parser.add_argument("--gui", action="store_true", help="Requires a desktop session/GPU, or Linux Xvfb/Mesa")
    parser.add_argument("--package", action="store_true", help="Test committed HEAD with real XTPKG")
    args = parser.parse_args()
    runtime = runtime_path(args.runtime)
    package_manager = args.xtpkg.resolve() / "src/main.luau"
    if not package_manager.is_file():
        parser.error("Pass --xtpkg /path/to/xtpkg/source")
    with tempfile.TemporaryDirectory(prefix="xtgui tests ") as temporary:
        base = Path(temporary)
        env = os.environ.copy()
        env.update(XTPKG_CACHE_DIR=str(base / "cache"), XTPKG_CONFIG_HOME=str(base / "config"),
                   XTPKG_GLOBAL_DIR=str(base / "global"), GIT_TERMINAL_PROMPT="0",
                   PYTHONDONTWRITEBYTECODE="1")
        tests = ROOT / "tests"
        if args.xtest:
            xtest_source = base / "xtest-source"
            execute(["git", "-c", "core.hooksPath=", "clone", "--local", "--no-hardlinks",
                     args.xtest.resolve(), xtest_source], base, env)
            # Test the current working sources without modifying the committed test manifest/lock.
            tests = base / "suite/tests"
            tests.mkdir(parents=True)
            shutil.copytree(ROOT / "src", tests.parent / "src")
            for script in (ROOT / "tests").glob("*.luau"):
                shutil.copy2(script, tests / script.name)
            (tests / "xtpkg.toml").write_text(
                '[package]\nname="xtgui-tests"\nversion="0.1.0"\nentry="main.luau"\n'
                '[dependencies]\nxtest=' + json.dumps("path:" + xtest_source.as_posix()) + '\n',
                encoding="utf-8")
        # Explicit registry overrides are respected; no package hooks are executed.
        execute([runtime, package_manager, "install"], tests, env, 240)
        execute([runtime, package_manager, "install", "--frozen"], tests, env)
        execute([runtime, tests / "main.luau"], env=env)
        if args.gui:
            fixture = base / "native image fixture.png"
            png_fixture(fixture)
            execute([runtime, ROOT / "tests/native.luau"], env=env)
            for mode in ("empty", "reactive"):
                execute([runtime, ROOT / "tests/native-update-loops.luau", mode], env=env)
            execute([runtime, ROOT / "tests/native-widgets.luau", fixture], env=env)
            for name in ("hello", "calculator", "settings", "editor", "gallery"):
                execute([runtime, ROOT / f"examples/{name}.luau", "--smoke"], env=env)
            unavailable = dict(env, WGPU_ADAPTER_NAME="xtgui-test-impossible-adapter-98a791")
            execute([runtime, ROOT / "tests/headless.luau"], env=unavailable)
        if args.package:
            execute([sys.executable, ROOT / "tests/package.py", "--runtime", runtime,
                     "--xtpkg", args.xtpkg.resolve()], env=env, timeout=300)
    print("XTGUI test run passed", flush=True)


if __name__ == "__main__":
    main()
