#!/usr/bin/env python3
"""
One-shot pbxproj patch: adds all 11 BolusPro_*.swift files to the
Loop.xcodeproj project. Mirrors the pattern used by
add_glucose_unit_context.py — picks an anchor sibling already in the
project and inserts new BuildFile/FileRef/Group/Sources entries after
each of its 8 anchor lines.

For pragmatism, every BolusPro file uses FoodFinder_FeatureFlags.swift
as its anchor. This means the files land in the FoodFinder group in
Xcode's navigator. A follow-up cleanup PR can move them into proper
BolusPro/ subgroups; the build is unaffected.

Deterministic UUIDs from md5(filename + role).
"""

import hashlib
import os
import re
import sys

# All BolusPro source files to add (paths relative to Loop/).
BOLUS_PRO_FILES = [
    "Models/BolusPro/BolusPro_Models.swift",
    "Resources/BolusPro/BolusPro_FeatureFlags.swift",
    "Services/BolusPro/BolusPro_FPUCalculator.swift",
    "Services/BolusPro/BolusPro_DataLayerHook.swift",
    "Services/BolusPro/BolusPro_BehaviorAnalyzer.swift",
    "Views/BolusPro/BolusPro_InfoSheet.swift",
    "Views/BolusPro/BolusPro_OnboardingView.swift",
    "Views/BolusPro/BolusPro_ManualMacroFields.swift",
    "Views/BolusPro/BolusPro_CarbEntrySection.swift",
    "Views/BolusPro/BolusPro_SettingsView.swift",
]

ANCHOR = "FoodFinder_FeatureFlags.swift"
PBXPROJ = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Loop.xcodeproj/project.pbxproj",
)


def uuid_for(path: str, role: str) -> str:
    h = hashlib.md5(f"{path}:{role}".encode()).hexdigest().upper()
    return h[:24]


def basename(path: str) -> str:
    return os.path.basename(path)


def main() -> int:
    with open(PBXPROJ, "r") as f:
        text = f.read()

    inserted = 0
    skipped = 0

    for relpath in BOLUS_PRO_FILES:
        fname = basename(relpath)
        if fname in text:
            print(f"⏭  {fname} already in pbxproj — skipping")
            skipped += 1
            continue

        text = insert_one(text, relpath, fname)
        if text is None:
            print(f"❌ Failed to insert {fname}")
            return 2
        inserted += 1
        print(f"✅ Inserted {fname}")

    with open(PBXPROJ, "w") as f:
        f.write(text)

    print(f"\nDone — inserted {inserted}, skipped {skipped}")
    return 0


def insert_one(text: str, relpath: str, fname: str):
    bf1 = uuid_for(relpath, "buildFile1")
    bf2 = uuid_for(relpath, "buildFile2")
    fr1 = uuid_for(relpath, "fileRef1")
    fr2 = uuid_for(relpath, "fileRef2")

    anchor_lines: list[tuple[int, str]] = []
    for i, line in enumerate(text.splitlines()):
        if ANCHOR in line and "Tests" not in line:
            anchor_lines.append((i, line))
    if len(anchor_lines) != 8:
        print(f"   ERROR: expected 8 anchor lines for {ANCHOR}, found {len(anchor_lines)}")
        return None

    bf1_anchor = anchor_lines[0][1]
    bf2_anchor = anchor_lines[1][1]
    fr1_anchor = anchor_lines[2][1]
    fr2_anchor = anchor_lines[3][1]
    g1_anchor = anchor_lines[4][1]
    g2_anchor = anchor_lines[5][1]
    s1_anchor = anchor_lines[6][1]
    s2_anchor = anchor_lines[7][1]

    def extract_uuid(line: str) -> str:
        m = re.match(r"\s*([0-9A-F]{24})\b", line)
        if not m:
            raise RuntimeError(f"Could not extract UUID from: {line.rstrip()}")
        return m.group(1)

    a_bf1 = extract_uuid(bf1_anchor)
    a_bf2 = extract_uuid(bf2_anchor)
    a_fr1 = extract_uuid(fr1_anchor)
    a_fr2 = extract_uuid(fr2_anchor)

    def patch(line: str, *substitutions: tuple[str, str]) -> str:
        out = line.replace(ANCHOR, fname)
        for old, new in substitutions:
            out = out.replace(old, new)
        return out

    # Anchor lives at Loop/Resources/FoodFinder/FoodFinder_FeatureFlags.swift,
    # so the FoodFinder group's path is "FoodFinder" inside "Resources".
    # New files live at Loop/<relpath>; the FileRef path must escape the
    # FoodFinder group (../) and the Resources group (../) and dive back
    # down into the correct subdirectory.
    relative_path = f"../../{relpath}"

    fr1_patched = patch(fr1_anchor, (a_fr1, fr1))
    fr2_patched = patch(fr2_anchor, (a_fr2, fr2))
    # Rewrite the FileRef path field so Xcode resolves the file at its
    # real location regardless of which navigator group hosts the entry.
    fr1_patched = re.sub(r"path\s*=\s*\S+?;", f"path = \"{relative_path}\";", fr1_patched)
    fr2_patched = re.sub(r"path\s*=\s*\S+?;", f"path = \"{relative_path}\";", fr2_patched)

    new_lines = {
        anchor_lines[0][0]: patch(bf1_anchor, (a_bf1, bf1), (a_fr1, fr1)),
        anchor_lines[1][0]: patch(bf2_anchor, (a_bf2, bf2), (a_fr2, fr2)),
        anchor_lines[2][0]: fr1_patched,
        anchor_lines[3][0]: fr2_patched,
        anchor_lines[4][0]: patch(g1_anchor, (a_fr1, fr1)),
        anchor_lines[5][0]: patch(g2_anchor, (a_fr2, fr2)),
        anchor_lines[6][0]: patch(s1_anchor, (a_bf1, bf1)),
        anchor_lines[7][0]: patch(s2_anchor, (a_bf2, bf2)),
    }

    lines = text.splitlines(keepends=True)
    for line_idx in sorted(new_lines.keys(), reverse=True):
        new_line = new_lines[line_idx]
        if not new_line.endswith("\n"):
            new_line += "\n"
        lines.insert(line_idx + 1, new_line)

    return "".join(lines)


if __name__ == "__main__":
    sys.exit(main())
