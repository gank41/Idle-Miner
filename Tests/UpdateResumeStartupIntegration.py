#!/usr/bin/env python3
"""Compile and launch real MinerApp against private receipts and inert sensors.
No engine is launched: each enabled state stays behind a normal safety guard.
"""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="idle-resume-startup-", dir="/private/tmp") as work:
    work = Path(work)
    app = work / "Resume Startup.app"
    macos = app / "Contents/MacOS"
    macos.mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    with (app / "Contents/Info.plist").open("wb") as out:
        plistlib.dump({"CFBundleIdentifier": "local.jeff.idleminer.resumestartupfixture", "CFBundleExecutable": "ResumeFixture", "CFBundleVersion": "13", "CFBundleShortVersionString": "1.9.1", "LSUIElement": True}, out)
    sources = [str(p) for p in sorted((ROOT / "Sources").glob("*.swift")) if p.name != "main.swift"]
    subprocess.run(["/usr/bin/swiftc", "-parse-as-library", "-module-cache-path", "/private/tmp/miner-swift-cache", "-framework", "AppKit", "-framework", "IOKit", "-F", str(ROOT / "Vendor/Sparkle"), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(ROOT / "Vendor/Sparkle"), *sources, str(ROOT / "Tests/UpdateResumeStartupIntegration.swift"), "-o", str(macos / "ResumeFixture")], check=True)
    for i, args in enumerate([[], ["--profile=DOGE"], ["--manual"], ["--manual", "--fixture-armed"], ["--login"], ["--login", "--login-off", "--start-mining"]]):
        state = work / f"state-{i}"
        state.mkdir()
        env = {**os.environ, "IDLE_MINER_STATE": str(state)}
        prepared = subprocess.run([str(macos / "ResumeFixture"), "--fixture-prepare", *args], env=env, check=True, text=True, capture_output=True, timeout=20)
        capability = prepared.stdout.strip()
        launch_args = [] if "--manual" in args else [f"--update-resume={capability}"]
        subprocess.run([str(macos / "ResumeFixture"), *args, *launch_args], env=env, check=True, timeout=20)
