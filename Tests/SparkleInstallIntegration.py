#!/usr/bin/env python3
"""Exercise a real, signed Sparkle update in disposable, spaced .app paths.

No production feed/keychain/app, wallet, mining engine or public endpoint is used.
Only this test's recorded PIDs may be terminated. Requires a GUI macOS session.
The report and fixture logs remain under /private/tmp; random keys are deleted.
"""
import base64
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import xml.sax.saxutils
import uuid

ROOT = Path(__file__).resolve().parents[1]
FRAMEWORK = ROOT / "Vendor/Sparkle/Sparkle.framework"
SIGN = ROOT / "Vendor/Sparkle/bin/sign_update"
WORK = Path(tempfile.mkdtemp(prefix="idle-sparkle-integration-", dir="/private/tmp"))
WALLET = "fake-public-wallet-preserved-outside-the-bundle\n"
BUNDLE_ID = "local.jeff.idleminer.updatefixture." + uuid.uuid4().hex
OVERALL_DEADLINE = time.monotonic() + 120


def run(*args, **kwargs):
    kwargs.setdefault("timeout", max(0.1, OVERALL_DEADLINE - time.monotonic()))
    result = subprocess.run([str(arg) for arg in args], check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs)
    return result.stdout


def events(path):
    if not path.exists():
        return []
    lines = path.read_text().splitlines()
    return [json.loads(line) for line in lines if line.strip()]


class FixtureServer(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        with (WORK / "http.log").open("a") as out:
            out.write(fmt % args + "\n")


def sign_app(app):
    run("/usr/bin/codesign", "--force", "--deep", "--sign", "-", app)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)


def make_app(path, binary, public, feed, report, state, build, cancel=False):
    contents = path / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    shutil.copy2(binary, contents / "MacOS/UpdaterFixture")
    run("/usr/bin/ditto", FRAMEWORK, contents / "Frameworks/Sparkle.framework")
    info = {
        "CFBundleExecutable": "UpdaterFixture", "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": "Updater Fixture", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0", "CFBundleVersion": str(build),
        "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
        "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False,
        "SUEnableSystemProfiling": False, "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True, "SUPublicEDKey": public,
        "SUFeedURL": feed, "FixtureReportPath": str(report),
        "FixtureStatePath": str(state), "FixtureCancelUpdate": cancel,
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True,
                                   "NSAllowsLocalNetworking": True},
    }
    with (contents / "Info.plist").open("wb") as target:
        plistlib.dump(info, target)
    broker = contents / "Helpers/Idle Miner Update Resume.app/Contents"
    (broker / "MacOS").mkdir(parents=True)
    shutil.copy2(binary, broker / "MacOS/UpdaterFixture")
    (broker / "Frameworks").mkdir()
    run("/usr/bin/ditto", FRAMEWORK, broker / "Frameworks/Sparkle.framework")
    with (broker / "Info.plist").open("wb") as out:
        plistlib.dump({"CFBundleIdentifier": BUNDLE_ID + ".broker", "CFBundleExecutable": "UpdaterFixture", "CFBundleName": "Update Resume Broker", "CFBundleVersion": str(build), "CFBundleShortVersionString": "1.0", "LSUIElement": True}, out)
    sign_app(broker.parent)
    sign_app(path)


def cleanup_pids(report):
    # Only fixture-owned app/worker/helper PIDs emitted by this particular run.
    for row in events(report):
        for key in ("pid", "peerPID"):
            pid = row.get(key)
            if not isinstance(pid, int) or pid <= 1:
                continue
            try:
                command = run("/bin/ps", "-p", pid, "-o", "command=")
                if str(WORK) in command and "UpdaterFixture" in command:
                    os.kill(pid, signal.SIGTERM)
            except (ProcessLookupError, subprocess.CalledProcessError):
                pass


def exercise(mode, binary, public, key, server):
    archive_format = "dmg" if mode.endswith("-dmg") else "zip"
    tampered = mode.startswith("tampered")
    cancelled = mode == "cancel"
    scenario = WORK / mode
    published = scenario / "published"
    published.mkdir(parents=True)
    installed = scenario / "Arbitrary Parent With Spaces" / "Updater Fixture.app"
    update = scenario / "New Release With Spaces" / "Updater Fixture.app"
    report = scenario / "events.jsonl"
    state = scenario / "isolated state with spaces"
    state.mkdir()
    (state / "fake-wallet.txt").write_text(WALLET)
    port = server.server_address[1]
    feed = f"http://127.0.0.1:{port}/{mode}/published/appcast.xml"
    make_app(installed, binary, public, feed, report, state, 1, cancelled)
    make_app(update, binary, public, feed, report, state, 2)
    archive = published / f"fixture-update.{archive_format}"
    if archive_format == "zip":
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", update, archive)
    else:
        stage = scenario / "Disk Image Root With Spaces"
        stage.mkdir()
        run("/usr/bin/ditto", update, stage / update.name)
        (stage / "Applications").symlink_to("/Applications", target_is_directory=True)
        (stage / "Sources").mkdir()
        shutil.copy2(ROOT / "Tests/SparkleInstallFixture.swift", stage / "Sources/SparkleInstallFixture.swift")
        (stage / "Sources/README.txt").write_text("Private Sparkle integration fixture source. No production miner.\n")
        run("/usr/bin/hdiutil", "create", "-ov", "-srcfolder", stage,
            "-volname", "Sparkle Update Fixture", "-format", "UDZO", archive)
    signature = run(SIGN, "--ed-key-file", key, "-p", archive).strip()
    if tampered:
        with archive.open("r+b") as stream:
            stream.seek(-1, os.SEEK_END)
            byte = stream.read(1)
            stream.seek(-1, os.SEEK_END)
            stream.write(bytes([byte[0] ^ 1]))
    url = f"http://127.0.0.1:{port}/{mode}/published/fixture-update.{archive_format}"
    (published / "appcast.xml").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>Private integration fixture</title><item>
<title>Fixture 1.0 build 2</title><description sparkle:descriptionFormat="plain-text"><![CDATA[Signed fixture release notes. No mining or public traffic.]]></description>
<enclosure url="{xml.sax.saxutils.escape(url)}" sparkle:version="2" sparkle:shortVersionString="1.0" sparkle:edSignature="{signature}" length="{archive.stat().st_size}" type="application/octet-stream"/>
</item></channel></rss>''')
    run(SIGN, "--ed-key-file", key, published / "appcast.xml")
    env = dict(os.environ)
    env["IDLE_MINER_STATE"] = str(state)
    # Launch the actual .app as an independent GUI process. Sparkle must replace
    # this exact path and launch the new build from its own installer helper.
    app_log = (scenario / "app.log").open("w")
    process = subprocess.Popen([str(installed / "Contents/MacOS/UpdaterFixture")],
                               env=env, stdout=app_log, stderr=subprocess.STDOUT)
    deadline = min(time.monotonic() + 105, OVERALL_DEADLINE)
    try:
        while time.monotonic() < deadline:
            rows = events(report)
            if any(row["event"] == "fixture-error" for row in rows):
                raise AssertionError(f"{mode}: fixture error: {rows}")
            if cancelled and any(row["event"] == "cancelled" for row in rows):
                break
            if not tampered and any(row["event"] == "relaunched" for row in rows):
                break
            if any(row["event"] == "rejected" for row in rows):
                if not tampered:
                    raise AssertionError(f"Valid signed fixture was rejected: {rows}")
                break
            time.sleep(0.1)
        else:
            raise AssertionError(f"{mode}: exceeded the 120-second overall deadline; events={events(report)}")
        rows = events(report)
        offer = next(row for row in rows if row["event"] == "offered")
        assert offer["installed"] == "1.0 (1)" and offer["latest"] == "1.0 (2)", offer
        assert offer["button"] == "Download and Install Now", offer
        assert "Signed fixture release notes" in offer["notes"], offer
        if cancelled:
            stopped_broker = next(row for row in rows if row["event"] == "cancelled")
            assert stopped_broker["workerRunning"] and stopped_broker["remainingPeers"] == 3, rows
            assert not any(row["event"] in ("prepared", "resume-armed", "terminating") for row in rows), rows
            assert not (state / "UpdateResume/receipt.json").exists(), rows
            assert (state / "fake-wallet.txt").read_text() == WALLET
            print("PASS: cancelled actual Sparkle check closes broker while preserving controller, three peers and worker", flush=True)
            return
        prepared = [row for row in rows if row["event"] == "prepared"]
        assert prepared and all(row["remainingPeers"] == 0 and not row["workerRunning"] and row["retainedWorkerLeases"] == 5 for row in prepared), rows
        assert any(row["event"] == "peer-terminated" for row in rows), rows
        with (installed / "Contents/Info.plist").open("rb") as source:
            installed_build = plistlib.load(source)["CFBundleVersion"]
        assert (state / "fake-wallet.txt").read_text() == WALLET
        for launched in (row for row in rows if row["event"] == "launched"):
            assert Path(launched["frameworkPath"]).resolve().is_relative_to(installed.resolve() / "Contents/Frameworks"), launched
        if not tampered:
            relaunched = next(row for row in rows if row["event"] == "relaunched")
            assert relaunched["build"] == "2" and installed_build == "2", rows
            assert Path(relaunched["path"]).resolve() == installed.resolve(), rows
            assert relaunched["wallet"] == WALLET, rows
            assert relaunched["resumed"] == {"ETH": True, "DOGE": True, "BTC": False, "LTC": False}, rows
            assert relaunched["primary"] == "ETH" and not relaunched["replayed"], rows
            assert any(row["event"] == "resume-armed" for row in rows), rows
            assert not (state / "UpdateResume/receipt.json").exists(), rows
            arguments = next(row for row in rows if row["event"] == "launched" and row["build"] == "2")["arguments"]
            assert len(arguments) == 2 and arguments[1].startswith("--update-resume="), rows
            assert any(row["event"] == "broker-opened" for row in rows), rows
        else:
            rejection = next(row for row in rows if row["event"] == "rejected")
            assert installed_build == "1" and not any(row["event"] == "relaunched" for row in rows), rows
            assert not (state / "UpdateResume/receipt.json").exists(), rows
            assert not any(row["event"] == "terminating" for row in rows), "Error cleanup quit the controller"
            assert re.search(r"sign(?:ature|ed|ing)", rejection["message"], re.I), rejection
        print(f"PASS: {mode} actual Sparkle {archive_format.upper()}, install build {installed_build}, exact spaced path, graceful peers/worker stop, exact single-use mining resume, preserved external wallet", flush=True)
    finally:
        cleanup_pids(report)
        try:
            process.wait(timeout=max(0.1, min(5, OVERALL_DEADLINE - time.monotonic())))
        except subprocess.TimeoutExpired:
            process.terminate()
        app_log.close()


def main():
    key = WORK / "random-fixture-private-key"
    public_file = WORK / "fixture-public-key"
    binary = WORK / "UpdaterFixture"
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(FixtureServer, directory=str(WORK)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        sources = ["Core.swift", "ProfileCoordination.swift", "UpdateCoordination.swift", "UpdateUserDriver.swift", "UpdateResume.swift", "UpdateResumeBroker.swift"]
        run("/usr/bin/swiftc", "-parse-as-library", "-module-cache-path", WORK / "swift-cache", "-framework", "AppKit", "-framework", "CryptoKit", "-F", ROOT / "Vendor/Sparkle", "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-rpath", "-Xlinker", ROOT / "Vendor/Sparkle", *[ROOT / "Sources" / name for name in sources], ROOT / "Tests/SparkleInstallFixture.swift", "-o", binary)
        run(binary, "--generate-key", key, public_file)
        assert key.stat().st_mode & 0o777 == 0o600
        public = public_file.read_text().strip()
        assert len(base64.b64decode(public)) == 32
        exercise("cancel", binary, public, key, server)
        exercise("valid", binary, public, key, server)
        exercise("tampered", binary, public, key, server)
        exercise("valid-dmg", binary, public, key, server)
        exercise("tampered-dmg", binary, public, key, server)
        assert set((WORK / "http.log").read_text().splitlines()) == {f'"GET /{mode}/published/{name} HTTP/1.1" 200 -' for mode in ("cancel", "valid", "tampered", "valid-dmg", "tampered-dmg") for name in (("appcast.xml",) if mode == "cancel" else ("appcast.xml", "fixture-update.dmg" if mode.endswith("-dmg") else "fixture-update.zip"))}, "Unexpected loopback request"
        (WORK / "summary.json").write_text(json.dumps({"cancelPreservesControllerPeersAndWorker": "passed", "brokerCapabilityRequired": True, "validZIPInstall": "passed", "tamperedZIPArchive": "rejected", "validDMGInstall": "passed", "tamperedDMGArchive": "rejected", "externalWallet": "preserved", "actualEmbeddedSparkle": "2.10.1", "productionEndpointOrKeychainUsed": False}, indent=2) + "\n")
    finally:
        key.unlink(missing_ok=True)
        server.shutdown()
        print(f"Fixture evidence: {WORK}", flush=True)


if __name__ == "__main__":
    main()
