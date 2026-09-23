#!/usr/bin/env python3
"""Converts the iOS string catalog into Android string resources.

Run from the repo root after changing ReadTime/Localizable.xcstrings:

    python3 android/tools/import_strings.py

Resource names are derived from the English key, so `s_daily_goal` in Kotlin is
the same text the iOS app shows. Plural keys become <plurals> entries.
"""

import json
import os
import re
import xml.etree.ElementTree as ET

SOURCE = "ReadTime/Localizable.xcstrings"
RES = "android/app/src/main/res"
# xcstrings language code -> Android resource folder suffix
LANGS = {"en": "", "vi": "-vi", "es": "-es", "ja": "-ja", "zh-Hans": "-b+zh+Hans"}
PLURAL_CATEGORIES = {"zero", "one", "two", "few", "many", "other"}


def resource_name(key: str) -> str:
    """A stable Android resource name for an English source string."""
    name = key.lower()
    name = name.replace("%lld", "n").replace("%@", "s").replace("%d", "n")
    name = re.sub(r"[^a-z0-9]+", "_", name).strip("_")
    name = re.sub(r"_+", "_", name)
    if not name:
        name = "text"
    return "s_" + name[:60].rstrip("_")


def convert_format(value: str) -> str:
    """iOS format specifiers to Java ones, numbered so translations may reorder them."""
    index = 0
    out = []
    i = 0
    while i < len(value):
        if value[i] == "%":
            # Already positional in the catalog, e.g. "%1$@" or "%2$lld".
            positional = re.match(r"%(\d+)\$(@|lld|d)", value[i:])
            if positional:
                kind = "s" if positional.group(2) == "@" else "d"
                out.append(f"%{positional.group(1)}${kind}")
                i += positional.end()
                continue
            if value.startswith("%lld", i):
                index += 1
                out.append(f"%{index}$d")
                i += 4
                continue
            if value.startswith("%@", i):
                index += 1
                out.append(f"%{index}$s")
                i += 2
                continue
            if value.startswith("%%", i):
                out.append("%%")
                i += 2
                continue
        out.append(value[i])
        i += 1
    return "".join(out)


def escape(value: str) -> str:
    value = value.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"')
    value = value.replace("\n", "\\n")
    return value


def main() -> None:
    catalog = json.load(open(SOURCE, encoding="utf-8"))
    entries = catalog["strings"]

    # Keys that are plurals in English must stay plurals in every language, or the
    # translation lands as a different resource type and Android falls back to English.
    plural_keys = {
        key
        for key, entry in entries.items()
        if "plural" in entry.get("localizations", {}).get("en", {}).get("variations", {})
        or any(
            "plural" in localization.get("variations", {})
            for localization in entry.get("localizations", {}).values()
        )
    }

    names = {}
    used = {}
    for key in sorted(entries):
        name = resource_name(key)
        if name in used:
            used[name] += 1
            name = f"{name}_{used[name]}"
        else:
            used[name] = 1
        names[key] = name

    for lang, suffix in LANGS.items():
        root = ET.Element("resources")
        root.set("xmlns:tools", "http://schemas.android.com/tools")
        if lang == "en":
            root.set("tools:ignore", "MissingTranslation")
        wrote = 0
        for key in sorted(entries):
            entry = entries[key]
            localization = entry.get("localizations", {}).get(lang)
            if lang == "en" and localization is None:
                # English keys are their own value in a string catalog.
                localization = {"stringUnit": {"value": key}}
            if localization is None:
                continue

            name = names[key]
            if key in plural_keys and "variations" not in localization:
                # This language has one form; give it to the "other" category.
                element = ET.SubElement(root, "plurals")
                element.set("name", name)
                item = ET.SubElement(element, "item")
                item.set("quantity", "other")
                item.text = convert_format(localization.get("stringUnit", {}).get("value", key))
                wrote += 1
                continue

            if "variations" in localization:
                plural = localization["variations"].get("plural")
                if not plural:
                    continue
                element = ET.SubElement(root, "plurals")
                element.set("name", name)
                for category, unit in plural.items():
                    if category not in PLURAL_CATEGORIES:
                        continue
                    item = ET.SubElement(element, "item")
                    item.set("quantity", category)
                    item.text = convert_format(unit["stringUnit"]["value"])
                wrote += 1
            else:
                value = localization.get("stringUnit", {}).get("value")
                if value is None:
                    continue
                element = ET.SubElement(root, "string")
                element.set("name", name)
                element.text = convert_format(value)
                wrote += 1

        for element in root.iter():
            if element.text:
                element.text = escape(element.text)

        folder = os.path.join(RES, f"values{suffix}")
        os.makedirs(folder, exist_ok=True)
        tree = ET.ElementTree(root)
        ET.indent(tree, space="    ")
        path = os.path.join(folder, "strings_catalog.xml")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write('<?xml version="1.0" encoding="utf-8"?>\n')
            handle.write(ET.tostring(root, encoding="unicode"))
            handle.write("\n")
        print(f"{path}: {wrote} strings")

    with open("android/tools/string_names.json", "w", encoding="utf-8") as handle:
        json.dump(names, handle, ensure_ascii=False, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
