"""Run upstream acoustic regressions through the actual OpenLess dynamic AEC boundary."""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

NATIVE = Path(__file__).resolve().parents[1] / "src-tauri"
VENDOR = NATIVE / "vendor/webrtc-aec3"


@unittest.skipUnless(platform.system() == "Darwin" and
                     int(platform.mac_ver()[0].split(".")[0] or 0) >= 15,
                     "the pinned AEC3 binary requires macOS 15 or later")
class MeetingEchoTests(unittest.TestCase):
    def test_real_bridge_preserves_near_speech_and_suppresses_echo(self):
        with tempfile.TemporaryDirectory(prefix="openless-aec-test-") as temporary:
            directory = Path(temporary)
            library = directory / "libOpenLessMeetingAEC.dylib"
            target = f"{platform.machine()}-apple-macosx15.0"
            subprocess.run([
                "xcrun", "clang++", "-dynamiclib", "-target", target,
                "-Wl,-install_name,@rpath/libOpenLessMeetingAEC.dylib", "-Wl,-all_load",
                "-I", str(VENDOR / "Sources/FluidAEC3Bridge/include"),
                "-x", "c", str(NATIVE / "src/meetings/aec/MeetingAECExports.c"), "-x", "none",
                str(VENDOR / "Artifacts/FluidAEC3.xcframework/macos-arm64_x86_64/libFluidAEC3-system-exact.a"),
                "-framework", "Foundation", "-o", str(library),
            ], check=True)
            functions = ["create_48k_mono", "destroy", "reset", "process_10ms",
                         "upstream_revision", "configuration_id"]
            executable = directory / "regression"
            subprocess.run([
                "xcrun", "clang++", "-std=c++17", "-O2", "-target", target,
                *[f"-Dfv_aec3_{name}=openless_aec3_{name}" for name in functions],
                str(VENDOR / "BridgeSources/phase1_bridge.cc"),
                "-L", str(directory), "-lOpenLessMeetingAEC",
                f"-Wl,-rpath,{directory}", "-o", str(executable),
            ], check=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True,
                                    text=True, timeout=60)
            self.assertIn("phase1_bridge_ok", result.stdout)
            self.assertIn("double_talk weak=1", result.stdout)
            print(result.stdout, end="")


if __name__ == "__main__":
    unittest.main()
