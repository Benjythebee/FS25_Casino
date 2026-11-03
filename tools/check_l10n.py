"""Checks the mod's XML files parse and the l10n files agree.

    python tools/check_l10n.py

- every language has the same keys and the same %s/%d placeholders as English
- entries start with a capital letter (ModHub guideline 5.5)
- every key used by the layout ($l10n_...) or the scripts ("casino_...") exists
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

MOD = Path(__file__).resolve().parent.parent / "FS25_Casino"
LANGUAGES = ("en", "de", "fr")

problems = []
for path in MOD.rglob("*.xml"):
    try:
        ET.parse(path)
    except ET.ParseError as err:
        problems.append(f"{path.name}: {err}")

texts = {}
for lang in LANGUAGES:
    texts[lang] = {e.get("k"): e.get("v") for e in ET.parse(MOD / "l10n" / f"l10n_{lang}.xml").iter("e")}
english = texts["en"]

for lang, entries in texts.items():
    for key in sorted(set(english) ^ set(entries)):
        problems.append(f"{lang}: key {key} only in one of en/{lang}")
    for key, value in entries.items():
        if re.findall(r"%[sd]", value) != re.findall(r"%[sd]", english.get(key, "")):
            problems.append(f"{lang}: {key} placeholders differ from en")
        if value[:1].isalpha() and not value[:1].isupper():
            problems.append(f"{lang}: {key} does not start with a capital letter: {value!r}")

used = set(re.findall(r"\$l10n_(\w+)", (MOD / "gui" / "CasinoFrame.xml").read_text(encoding="utf-8")))
for script in MOD.rglob("*.lua"):
    used |= set(re.findall(r'"(casino_\w+)"', script.read_text(encoding="utf-8")))
for key in sorted(used):
    if key not in english and not key.endswith("_"):
        problems.append(f"key {key} is used but missing from l10n_en.xml")

for problem in problems:
    print("FAIL " + problem)
print(f"{len(english)} keys x {len(LANGUAGES)} languages, {len(problems)} problems")
sys.exit(1 if problems else 0)
