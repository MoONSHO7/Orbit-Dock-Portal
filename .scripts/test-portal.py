"""Exercise Portal's real TOC in Lua 5.1 using explicit native/host doubles.

These checks cover source integration and ownership, not protected WoW execution.
"""

from pathlib import Path
import re
import xml.etree.ElementTree as ET

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / ".scripts/tests/portal_native.lua"
CASES = ROOT / ".scripts/tests/portal_cases.lua"


def scripts(path):
    if path.suffix == ".xml":
        for element in ET.parse(path).getroot():
            if element.tag.rsplit("}", 1)[-1] in ("Script", "Include"):
                yield from scripts(path.parent / element.attrib["file"].replace("\\", "/"))
    else:
        yield path


loaded = []
for line in (ROOT / "Orbit_Portal.toc").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        loaded.extend(scripts(ROOT / line.replace("\\", "/")))

lua = LuaRuntime()
compile_lua = lua.eval("function(source, name) assert(loadstring(source, name)) end")
for path in ROOT.rglob("*.lua"):
    compile_lua(path.read_text(encoding="utf-8"), str(path))

scenarios = ("standalone", "disabled", "blocked", "future", "corrupt", "legacy", "oldhost", "loaderror", "movementerror")
for scenario in scenarios:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FIXTURE.read_text(encoding="utf-8"), scenario)
    loader = lua.eval("function(source, name) assert(loadstring(source, name))('Orbit_Portal', addon) end")
    for path in loaded:
        loader(path.read_text(encoding="utf-8"), str(path))
    lua.execute(CASES.read_text(encoding="utf-8"), scenario)
    print(f"PASS: real TOC/XML {scenario}")

keys = set()
for path in (ROOT / "Core").rglob("*.lua"):
    keys.update(re.findall(r"\bL\.([A-Z][A-Z0-9_]*)", path.read_text(encoding="utf-8")))
for locale in ("enUS", "deDE", "frFR", "esES", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FIXTURE.read_text(encoding="utf-8"), "locale")
    lua.execute("local locale = ...; GetLocale = function() return locale end", locale)
    loader = lua.eval("function(source) assert(loadstring(source))('Orbit_Portal', addon) end")
    for path in loaded:
        if path.parent.name == "Localization":
            loader(path.read_text(encoding="utf-8"))
    for key in keys:
        assert isinstance(lua.globals().addon.L[key], str), (locale, key)
print(f"PASS: Lua 5.1 compilation and {len(keys)} referenced localization keys across nine locales")
