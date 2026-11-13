#!/usr/bin/env python3
"""Check a fresh Quill workstation; optionally write ignored local SDK/environment paths."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FLUTTER_VERSION = "3.47.9"
NDK_VERSION = "28.2.13676358"


def property_value(value):
    return str(value).replace("\\", "\\\\").replace(":", "\\:")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-sdk", type=Path)
    parser.add_argument("--android-sdk", type=Path)
    parser.add_argument("--java-home", type=Path)
    parser.add_argument("--android-user-home", type=Path)
    parser.add_argument("--configure", action="store_true", help="write ignored local.properties and environment files")
    parser.add_argument("--require-existing-key", action="store_true", help="fail if the existing Android debug keystore is absent")
    args = parser.parse_args()
    flutter_command = shutil.which("flutter")
    flutter = args.flutter_sdk or (Path(flutter_command).resolve().parent.parent if flutter_command else ROOT / ".local/toolchains/flutter")
    android = args.android_sdk or Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or Path.home() / "Library/Android/sdk")
    java = args.java_home or (Path(os.environ["JAVA_HOME"]) if os.environ.get("JAVA_HOME") else None)
    android_user = args.android_user_home or Path(os.environ.get("ANDROID_USER_HOME") or Path.home() / ".android")
    flutter, android, android_user = (p.expanduser().resolve() for p in (flutter, android, android_user))
    errors = []
    version_file = flutter / "bin/cache/flutter.version.json"
    try:
        version = json.loads(version_file.read_text())["frameworkVersion"]
        if version != FLUTTER_VERSION:
            errors.append(f"Flutter {FLUTTER_VERSION} required; found {version}")
    except (OSError, ValueError, KeyError):
        errors.append(f"Initialize Flutter {FLUTTER_VERSION} with flutter --version: {flutter}")
    if not any((android / "platforms" / name / "android.jar").is_file() for name in ("android-37.0", "android-37")):
        errors.append("Android SDK platform 37.0 is missing")
    for part in ("build-tools/36.0.0", f"ndk/{NDK_VERSION}", "platform-tools"):
        if not (android / part).is_dir():
            errors.append(f"Android SDK component missing: {part}")
    if java:
        java = java.expanduser().resolve()
        binary = java / "bin" / ("java.exe" if os.name == "nt" else "java")
        try:
            result = subprocess.run([str(binary), "-version"], capture_output=True, text=True, timeout=15, check=True)
            if not re.search(r'(?:version\s+\")?21(?:\.|\")', result.stderr + result.stdout):
                errors.append("JDK 21 is required")
        except (OSError, subprocess.SubprocessError):
            errors.append(f"Cannot run JDK 21 from {java}")
    else:
        errors.append("Set JAVA_HOME or pass --java-home for JDK 21")
    # Optional: a sibling device-lease tool (orbit) for sharing a phone/emulator between sessions.
    orbit = ROOT.parent / "orbit"
    key = android_user / "debug.keystore"
    if args.require_existing_key and not key.is_file():
        errors.append("Transfer the existing signing keystore securely before updating the existing phone")
    if errors:
        for error in errors:
            print(f"MISSING: {error}")
        return 1
    print(f"Toolchain ready: Flutter {FLUTTER_VERSION}, JDK 21, Android 37.0, NDK {NDK_VERSION}")
    print("Existing signing keystore:", "present (verify its certificate before phone updates)" if key.is_file() else "absent; do not update the existing phone yet")
    if not args.configure:
        print("Check only; no files changed. Use --configure to write ignored workstation paths.")
        return 0
    properties = ROOT / "mobile/android/local.properties"
    previous = properties.read_text() if properties.exists() else ""
    lines = [line for line in previous.splitlines() if not re.match(r"^(sdk\.dir|flutter\.sdk)\s*[=:]", line)]
    lines += [f"sdk.dir={property_value(android.as_posix())}", f"flutter.sdk={property_value(flutter.as_posix())}"]
    properties.write_text("\n".join(lines) + "\n")
    local = ROOT / ".local"
    local.mkdir(exist_ok=True)
    # Flutter hands Gradle its own jdk-dir (global config or Android Studio's JBR), which can be
    # older than 21 and fails with "invalid source release". Pin JDK 21 in Quill's Gradle home.
    gradle_props = local / "gradle-cache/gradle.properties"
    gradle_props.parent.mkdir(parents=True, exist_ok=True)
    old_props = gradle_props.read_text() if gradle_props.exists() else ""
    kept = [line for line in old_props.splitlines() if not re.match(r"^org\.gradle\.java\.home\s*[=:]", line)]
    gradle_props.write_text("\n".join(kept + [f"org.gradle.java.home={property_value(java.as_posix())}"]) + "\n")
    values = {
        "JAVA_HOME": str(java), "ANDROID_HOME": str(android), "ANDROID_SDK_ROOT": str(android),
        "ANDROID_USER_HOME": str(android_user), "PUB_CACHE": str(local / "pub-cache"),
        "GRADLE_USER_HOME": str(local / "gradle-cache"),
        "ANALYZER_STATE_LOCATION_OVERRIDE": str(local / "analyzer-cache"),
    }
    if (orbit / "tools/orbit_coord.py").is_file():
        values["ORBIT_COORDINATION_DIR"] = str(orbit / ".orbit-coordination/0.3")
    paths = [str(flutter / "bin"), str(android / "platform-tools")]
    shell = "# Generated local workstation paths; never commit this file.\n"
    shell += "\n".join(f"export {k}={shlex.quote(v)}" for k, v in values.items())
    shell += f'\nexport PATH={shlex.quote(":".join(paths))}:"$PATH"\n'
    (local / "quill-env.sh").write_text(shell)
    ps = "# Generated local workstation paths; never commit this file.\n"
    ps += "\n".join("$env:" + k + " = '" + v.replace("'", "''") + "'" for k, v in values.items())
    ps += "\n$env:PATH = '" + ";".join(paths).replace("'", "''") + "' + ';' + $env:PATH\n"
    (local / "quill-env.ps1").write_text(ps)
    print("Wrote mobile/android/local.properties, .local/quill-env.{sh,ps1} and .local/gradle-cache/gradle.properties")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
