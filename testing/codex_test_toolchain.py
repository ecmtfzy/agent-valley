"""Locate a macOS Swift toolchain for the standalone Codex smoke tests.

SDKROOT may name an SDK (for example macosx) or its directory. DEVELOPER_DIR
selects a developer installation explicitly. Otherwise prefer installed Command
Line Tools, which do not require accepting the full Xcode application's license,
then fall back to xcrun's configured developer directory. This never changes
xcode-select or accepts a license. Running this file only prints the selection.
"""
import json
import os
from pathlib import Path
import re
import subprocess


def swift_toolchain():
    environment = dict(os.environ)
    explicit_developer = environment.get("DEVELOPER_DIR")
    requested_sdk = environment.get("SDKROOT", "").strip()
    sdk_path = None
    sdk_name = "macosx"
    if requested_sdk:
        path = Path(requested_sdk).expanduser()
        if path.is_dir():
            sdk_path = str(path.resolve())
        elif re.fullmatch(r"macosx(?:\d+(?:\.\d+)*)?", requested_sdk):
            sdk_name = requested_sdk
        else:
            raise RuntimeError("SDKROOT must name an existing SDK directory or a macosx SDK")

    candidates = [environment]
    clt = Path("/Library/Developer/CommandLineTools")
    if not explicit_developer and (clt / "usr/bin/swiftc").is_file():
        candidates.insert(0, dict(environment, DEVELOPER_DIR=str(clt)))

    failures = []
    for candidate in candidates:
        def locate(option):
            answer = subprocess.run(["/usr/bin/xcrun", "--sdk", sdk_name, *option],
                                    env=candidate, capture_output=True, text=True, timeout=10)
            if answer.returncode != 0:
                reason = answer.stderr.strip().replace("\n", " ")[:240]
                raise RuntimeError(reason or "xcrun could not locate the macOS toolchain")
            return answer.stdout.strip()

        try:
            compiler = locate(["--find", "swiftc"])
            sdk = sdk_path or locate(["--show-sdk-path"])
            if not Path(compiler).is_file() or not os.access(compiler, os.X_OK) or not Path(sdk).is_dir():
                raise RuntimeError("xcrun returned an unavailable Swift compiler or SDK")
            return compiler, sdk, dict(candidate, SDKROOT=sdk)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            failures.append(str(error))

    raise RuntimeError("No usable macOS Swift toolchain; set DEVELOPER_DIR and/or SDKROOT. "
                       + "; ".join(failures))


if __name__ == "__main__":
    compiler, sdk, environment = swift_toolchain()
    print(json.dumps({"swiftc": compiler, "sdk": sdk,
                      "developer_dir": environment.get("DEVELOPER_DIR")}, indent=2))
