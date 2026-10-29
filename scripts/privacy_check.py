#!/usr/bin/env python3
"""Review tracked files for accidental private data; never print matched values."""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = {
    "credential token": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|sk-(?:proj-)?[A-Za-z0-9_-]{24,})"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "personal home path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "private tailnet hostname": re.compile(r"(?<![A-Za-z0-9.-])(?!mac-mini\.example\.ts\.net\b|mac-mini\.your-tailnet\.ts\.net\b)[a-zA-Z0-9.-]+\.ts\.net\b"),
    "literal signing team": re.compile(r"DEVELOPMENT_TEAM\s*[:=]\s*[\"']?[A-Z0-9]{10}\b"),
    "personal email": re.compile(r"\b[A-Za-z0-9._%+-]+@(?!(?:2x|3x)\.png\b|users\.noreply\.github\.com\b|example\.(?:com|org|net)\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "assigned secret": re.compile(r'''(?i)(?:password|access_token|refresh_token|api_key)\s*["']?\s*[:=]\s*["'][^"'\s]{8,}["']'''),
}
VIN = re.compile(r"\b[A-HJ-NPR-Z0-9]{17}\b")
PRIVATE_IPV4 = re.compile(r"\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b")
BLOCKED_SUFFIXES = {".log", ".db", ".sqlite", ".sqlite3", ".p12", ".p8", ".pem", ".key", ".mobileprovision", ".xcuserstate"}
TEXT_SUFFIXES = {".swift", ".metal", ".py", ".sh", ".yml", ".yaml", ".json", ".md", ".txt", ".svg", ".plist", ".entitlements", ".pbxproj", ".xcscheme", ".xcworkspacedata"}


def findings(path: str, text: str) -> list[str]:
    """Pure matching function so the publication guard can be regression tested."""
    result = [name for name, pattern in RULES.items() if pattern.search(text)]
    if PRIVATE_IPV4.search(text):
        result.append("private network address")
    if VIN.search(text):
        result.append("unexpected vehicle identifier")
    return result


def main() -> int:
    try:
        output = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    except subprocess.CalledProcessError:
        print("Run this guard inside the prepared Git repository.")
        return 2
    paths = [Path(p) for p in output.decode().split("\0") if p]
    if not paths:
        print("No tracked files to check. Stage the intended public files first.")
        return 2
    failures = []
    for relative in paths:
        label = relative.as_posix()
        if relative.suffix.lower() in BLOCKED_SUFFIXES or relative.name.startswith(".env") or "xcuserdata" in relative.parts or "data" in relative.parts:
            failures.append((label, "private runtime or signing file"))
            continue
        path = ROOT / relative
        if path.is_symlink():
            failures.append((label, "symlink requires manual review"))
            continue
        # Git may contain a path deleted in the working tree.
        if not path.exists():
            failures.append((label, "tracked file missing from working tree"))
            continue
        if relative.suffix in TEXT_SUFFIXES or not relative.suffix:
            text = path.read_text(encoding="utf-8")
            failures.extend((label, rule) for rule in findings(label, text))
    for path, rule in failures:
        print(f"FAIL {path}: {rule}")
    if failures:
        print(f"Review required: {len(failures)} finding(s). Matching values are withheld.")
        return 1
    print(f"Privacy guard passed for {len(paths)} tracked files. Review images separately.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
