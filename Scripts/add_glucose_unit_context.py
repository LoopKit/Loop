#!/usr/bin/env python3
"""
One-shot pbxproj patch: adds LoopInsights_GlucoseUnitContext.swift to the
Loop.xcodeproj project. Mirrors how LoopInsights_DataAggregator.swift is wired
(two BuildFile entries, two FileRef entries, two LoopInsights group entries,
two Sources phase entries — Loop + LoopWatch targets).

Deterministic UUIDs from md5(filename + role).
"""

import hashlib
import os
import re
import sys

FILENAME = "LoopInsights_GlucoseUnitContext.swift"
PBXPROJ = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Loop.xcodeproj/project.pbxproj",
)
ANCHOR = "LoopInsights_DataAggregator.swift"


def uuid_for(role: str) -> str:
    h = hashlib.md5(f"{FILENAME}:{role}".encode()).hexdigest().upper()
    return h[:24]


def main() -> int:
    with open(PBXPROJ, "r") as f:
        text = f.read()

    if FILENAME in text:
        print(f"{FILENAME} already in pbxproj — nothing to do")
        return 0

    bf1 = uuid_for("buildFile1")
    bf2 = uuid_for("buildFile2")
    fr1 = uuid_for("fileRef1")
    fr2 = uuid_for("fileRef2")

    # Find every line that mentions the anchor file. Each one is a template
    # we'll mirror with our new file. Lines come in 8 flavors total (8 anchor
    # lines for the .swift file in DataAggregator's case + tests we ignore).
    anchor_lines: list[tuple[int, str]] = []
    for i, line in enumerate(text.splitlines()):
        if ANCHOR in line and "Tests" not in line:
            anchor_lines.append((i, line))
    if len(anchor_lines) != 8:
        print(f"ERROR: expected 8 non-test anchor lines, found {len(anchor_lines)}")
        for ln in anchor_lines:
            print(f"  line {ln[0]+1}: {ln[1].strip()}")
        return 2

    # Sort by line number, walk through them. The 8 lines, in order:
    #   1. PBXBuildFile (target A)        -> uses bf1, fr1
    #   2. PBXBuildFile (target B)        -> uses bf2, fr2
    #   3. PBXFileReference (target A)    -> defines fr1
    #   4. PBXFileReference (target B)    -> defines fr2
    #   5. PBXGroup children (target A)   -> references fr1
    #   6. PBXGroup children (target B)   -> references fr2
    #   7. PBXSourcesBuildPhase (target A) -> references bf1
    #   8. PBXSourcesBuildPhase (target B) -> references bf2
    # Construct each replacement line by substituting UUIDs into the anchor.

    bf1_anchor = anchor_lines[0][1]
    bf2_anchor = anchor_lines[1][1]
    fr1_anchor = anchor_lines[2][1]
    fr2_anchor = anchor_lines[3][1]
    g1_anchor = anchor_lines[4][1]
    g2_anchor = anchor_lines[5][1]
    s1_anchor = anchor_lines[6][1]
    s2_anchor = anchor_lines[7][1]

    # Build new lines by replacing the anchor file's UUIDs and filename in
    # each template. Extract the anchor's UUIDs from the BuildFile and
    # FileRef lines.
    def extract_uuid(line: str) -> str:
        m = re.match(r"\s*([0-9A-F]{24})\b", line)
        if not m:
            raise RuntimeError(f"Could not extract UUID from: {line.rstrip()}")
        return m.group(1)

    anchor_bf1 = extract_uuid(bf1_anchor)
    anchor_bf2 = extract_uuid(bf2_anchor)
    anchor_fr1 = extract_uuid(fr1_anchor)
    anchor_fr2 = extract_uuid(fr2_anchor)

    def patch(line: str, *substitutions: tuple[str, str]) -> str:
        out = line.replace(ANCHOR, FILENAME)
        for old, new in substitutions:
            out = out.replace(old, new)
        return out

    new_lines = {
        anchor_lines[0][0]: patch(bf1_anchor, (anchor_bf1, bf1), (anchor_fr1, fr1)),
        anchor_lines[1][0]: patch(bf2_anchor, (anchor_bf2, bf2), (anchor_fr2, fr2)),
        anchor_lines[2][0]: patch(fr1_anchor, (anchor_fr1, fr1)),
        anchor_lines[3][0]: patch(fr2_anchor, (anchor_fr2, fr2)),
        anchor_lines[4][0]: patch(g1_anchor, (anchor_fr1, fr1)),
        anchor_lines[5][0]: patch(g2_anchor, (anchor_fr2, fr2)),
        anchor_lines[6][0]: patch(s1_anchor, (anchor_bf1, bf1)),
        anchor_lines[7][0]: patch(s2_anchor, (anchor_bf2, bf2)),
    }

    # Insert each new line immediately after its anchor. Walk lines in reverse
    # so earlier insertions don't shift later anchor indices.
    lines = text.splitlines(keepends=True)
    for line_idx in sorted(new_lines.keys(), reverse=True):
        new_line = new_lines[line_idx]
        if not new_line.endswith("\n"):
            new_line += "\n"
        lines.insert(line_idx + 1, new_line)

    out = "".join(lines)

    with open(PBXPROJ, "w") as f:
        f.write(out)

    print(f"Inserted {FILENAME} with UUIDs:")
    print(f"  buildFile1 = {bf1}")
    print(f"  buildFile2 = {bf2}")
    print(f"  fileRef1   = {fr1}")
    print(f"  fileRef2   = {fr2}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
