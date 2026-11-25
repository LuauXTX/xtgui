"""Run an installed application unchanged, closing it after proven GPU frames.

The temporary driver lives beside the entrypoint so LuauXTX's real require
closure resolves relative and package imports exactly as in the application.
"""
import argparse,json,os,subprocess,tempfile,tomllib
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--runtime',type=Path,required=True);parser.add_argument('--project',type=Path,required=True);args=parser.parse_args()
project=args.project.resolve();manifest=tomllib.loads((project/'xtpkg.toml').read_text(encoding='utf8'))
entry=(project/manifest['package']['entry']).resolve()
if not entry.is_file() or not entry.is_relative_to(project):raise SystemExit('Entrypoint must be a file inside the project')
record=json.loads((project/'packages/.xtpkg-imports.json').read_text(encoding='utf8'))['xtgui']
packages=(project/'packages').resolve();package=(packages/record['path']).resolve()
if not package.is_relative_to(packages):raise SystemExit('XTGUI record escapes packages')
application=package/'src/core/Application.luau'
source=Path(__file__).with_suffix('.luau').read_text(encoding='utf8')
with tempfile.NamedTemporaryFile(mode='w',encoding='utf8',prefix='.xtpkg-smoke-',suffix='.luau',dir=entry.parent,delete=False) as handle:
    handle.write(source);driver=Path(handle.name)
try:
    result=subprocess.run([str(args.runtime.resolve()),str(driver),str(entry),str(application)],cwd=project,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=60)
    print(result.stdout,end='');print(result.stderr,end='')
    if result.returncode:raise SystemExit(result.returncode)
finally:driver.unlink(missing_ok=True)
