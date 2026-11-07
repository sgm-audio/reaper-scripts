"""Export plugin identifiers from REAPER's VST cache to JSON."""

import argparse
import csv
import json
import os
import platform
import sys


def get_reaper_resource_path(prompt=False):
    """Return the standard REAPER resource path, or ``None`` if it is absent.

    Set ``prompt=True`` for an interactive CLI fallback. Missing environment
    variables (notably APPDATA on Windows) never cause an exception.
    """
    system = platform.system()
    path = None
    if system == "Windows" and os.getenv("APPDATA"):
        path = os.path.join(os.environ["APPDATA"], "REAPER")
    elif system == "Darwin":
        path = os.path.expanduser("~/Library/Application Support/REAPER")
    elif system == "Linux":
        path = os.path.expanduser("~/.config/REAPER")

    if path and os.path.isdir(path):
        return path
    if prompt and sys.stdin.isatty():
        entered = input("Enter full path to REAPER resource folder: ").strip()
        return os.path.abspath(os.path.expanduser(entered)) if entered else None
    return None


def parse_reaper_ini(ini_path):
    """Parse ``reaper-vstplugins64.ini`` into a name-keyed plugin mapping.

    REAPER stores ``filename=UID,project_id,"Name (Developer)"``. Using the CSV
    parser preserves quoted commas and removes the quotes around display names.
    """
    plugins = {}
    if not os.path.isfile(ini_path):
        print(f"[ERROR] Could not find {ini_path}", file=sys.stderr)
        return plugins

    print(f"Scanning: {ini_path}...")
    with open(ini_path, "r", encoding="utf-8-sig", errors="replace", newline="") as source:
        for raw_line in source:
            line = raw_line.strip()
            if not line or line.startswith("[") or "=" not in line:
                continue
            filename, data = line.split("=", 1)
            try:
                parts = next(csv.reader([data]))
            except (csv.Error, StopIteration):
                continue
            if len(parts) < 3:
                continue

            uid = parts[0].strip()
            name = ",".join(parts[2:]).strip()
            if not name:
                continue
            lower_name = filename.lower()
            plugin_type = "VST"
            if lower_name.endswith(".vst3"):
                plugin_type = "VST3"
            elif lower_name.endswith(".clap"):
                plugin_type = "CLAP"

            plugins[name] = {"uid": uid, "filename": filename, "type": plugin_type}
    return plugins


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource-path", help="REAPER resource directory")
    parser.add_argument("--ini", help="Explicit path to reaper-vstplugins64.ini")
    parser.add_argument(
        "-o", "--output", default="reaper_plugin_map.json", help="Output JSON file"
    )
    args = parser.parse_args(argv)

    ini_path = args.ini
    if not ini_path:
        resource_path = args.resource_path or get_reaper_resource_path(prompt=True)
        if not resource_path:
            print(
                "Could not auto-detect REAPER. Pass --resource-path or --ini.",
                file=sys.stderr,
            )
            return 2
        ini_path = os.path.join(resource_path, "reaper-vstplugins64.ini")

    plugins = parse_reaper_ini(ini_path)
    if not plugins:
        print("No plugins found. Check the cache path and rescan plugins in REAPER.", file=sys.stderr)
        return 1

    with open(args.output, "w", encoding="utf-8") as output:
        json.dump(plugins, output, indent=4, ensure_ascii=False)
        output.write("\n")
    print(f"[SUCCESS] Extracted {len(plugins)} plugins.")
    print(f"Map saved to: {os.path.abspath(args.output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
