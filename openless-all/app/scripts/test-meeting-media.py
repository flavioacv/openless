"""Exercise the production Swift decoder without requesting microphone/screen permissions."""
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import tempfile
import unittest
import wave

APP = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "native media adapter requires macOS")
class MeetingMediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="openless-media-tests-")
        cls.directory = Path(cls.workspace.name)
        configured = os.environ.get("OPENLESS_MEETING_MEDIA_PROBE")
        if configured:
            cls.probe = Path(configured)
            if not cls.probe.is_file():
                raise RuntimeError("OPENLESS_MEETING_MEDIA_PROBE does not point to a built production probe")
        else:
            package = APP / "src-tauri"
            subprocess.run(["xcrun", "swift", "build", "--package-path", str(package),
                            "--product", "MeetingMediaProbe", "-j", "4"], check=True)
            output = subprocess.run(["xcrun", "swift", "build", "--package-path", str(package),
                                     "--show-bin-path"], check=True, capture_output=True, text=True)
            cls.probe = Path(output.stdout.strip()) / "MeetingMediaProbe"

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def fixture(self, name, seconds):
        path = self.directory / name
        frames = struct.pack("<" + "h" * 8820, *[
            int(10000 * math.sin(index * 2 * math.pi * 440 / 44100))
            for index in range(4410) for _ in range(2)
        ])
        with wave.open(str(path), "wb") as audio:
            audio.setnchannels(2)
            audio.setsampwidth(2)
            audio.setframerate(44100)
            for _ in range(round(seconds * 10)):
                audio.writeframes(frames)
        return path

    def run_import(self, source):
        destination = self.directory / (source.stem + "-decoded")
        result = subprocess.run([str(self.probe), str(source), str(destination)],
                                capture_output=True, text=True, timeout=90)
        return result, destination

    def test_stereo_resampling_preserves_duration_and_original(self):
        source = self.fixture("stereo.wav", 2)
        digest = hashlib.sha256(source.read_bytes()).digest()
        result, destination = self.run_import(source)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        response = json.loads(result.stdout)
        self.assertFalse(response["video"])
        self.assertEqual(len(response["blocks"]), 1)
        self.assertEqual(response["blocks"][0]["durationMs"], 2000)
        self.assertEqual(response["blocks"][0]["startMs"], 0)
        self.assertEqual(hashlib.sha256(source.read_bytes()).digest(), digest)
        self.assertTrue((destination / response["blocks"][0]["relativePath"]).is_file())

    def test_long_import_publishes_bounded_recoverable_blocks_without_timeline_drift(self):
        source = self.fixture("long.wav", 61.5)
        result, destination = self.run_import(source)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        blocks = json.loads(result.stdout)["blocks"]
        self.assertEqual([block["durationMs"] for block in blocks], [60000, 1500])
        self.assertEqual([block["startMs"] for block in blocks], [0, 60000])
        self.assertTrue(all(block["byteCount"] < 2_000_000 for block in blocks))
        self.assertEqual(json.loads((destination / "media.json").read_text()), blocks)

    def test_invalid_audio_returns_an_error_without_touching_the_original(self):
        source = self.directory / "invalid.wav"
        source.write_bytes(b"not audio")
        result, _ = self.run_import(source)
        self.assertEqual(result.returncode, 1)
        self.assertIn("error", json.loads(result.stdout))
        self.assertEqual(source.read_bytes(), b"not audio")

    @unittest.skipUnless(shutil.which("ffmpeg"), "video fixture creation uses an existing ffmpeg installation")
    def test_real_video_track_and_audio_are_imported_without_changing_the_movie(self):
        audio = self.fixture("movie-source.wav", 2)
        movie = self.directory / "meeting.mov"
        creation = subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=32x32:r=10:d=2",
                                   "-i", str(audio), "-c:v", "mpeg4", "-c:a", "aac", "-t", "2", str(movie)],
                                   capture_output=True, text=True, timeout=60)
        self.assertEqual(creation.returncode, 0, creation.stderr + creation.stdout)
        digest = hashlib.sha256(movie.read_bytes()).digest()
        result, destination = self.run_import(movie)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        response = json.loads(result.stdout)
        self.assertTrue(response["video"])
        self.assertLessEqual(abs(sum(block["durationMs"] for block in response["blocks"]) - 2000), 2)
        self.assertTrue(all((destination / block["relativePath"]).is_file() for block in response["blocks"]))
        self.assertEqual(hashlib.sha256(movie.read_bytes()).digest(), digest)

    @unittest.skipUnless(shutil.which("ffmpeg"), "video fixture creation uses an existing ffmpeg installation")
    def test_pcm_movie_imports_natively_and_ignores_empty_end_markers(self):
        audio = self.fixture("pcm-movie-source.wav", 2)
        movie = self.directory / "pcm-meeting.mov"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=32x32:r=10:d=2",
                        "-i", str(audio), "-c:v", "mpeg4", "-c:a", "pcm_s16le", "-ar", "16000", "-ac", "1",
                        "-t", "2", str(movie)], check=True, capture_output=True, text=True, timeout=60)
        destination = self.directory / "pcm-movie-native"
        environment = {**os.environ, "OPENLESS_MEETING_NATIVE_ONLY": "1"}
        result = subprocess.run([str(self.probe), str(movie), str(destination)], env=environment,
                                capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        response = json.loads(result.stdout)
        self.assertTrue(response["video"])
        self.assertNotEqual(response.get("decoder"), "ffmpeg")
        self.assertEqual(sum(block["durationMs"] for block in response["blocks"]), 2000)

    @unittest.skipUnless(shutil.which("ffmpeg"), "compressed audio fixture uses an existing ffmpeg installation")
    def test_aac_uses_local_fallback_without_crashing_or_modifying_the_source(self):
        audio = self.fixture("aac-source.wav", 2)
        compressed = self.directory / "compressed.m4a"
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(audio), "-c:a", "aac", str(compressed)],
                       check=True, capture_output=True, text=True, timeout=60)
        digest = hashlib.sha256(compressed.read_bytes()).digest()
        result, _ = self.run_import(compressed)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        response = json.loads(result.stdout)
        self.assertFalse(response["video"])
        self.assertLessEqual(abs(sum(block["durationMs"] for block in response["blocks"]) - 2000), 2)
        self.assertEqual(hashlib.sha256(compressed.read_bytes()).digest(), digest)

    def test_upsampling_8khz_does_not_invent_gaps_between_decoder_callbacks(self):
        source = self.directory / "telephone.wav"
        with wave.open(str(source), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(8000)
            audio.writeframes(struct.pack("<" + "h" * 72000, *[
                int(10000 * math.sin(index * 2 * math.pi * 330 / 8000))
                for index in range(72000)
            ]))
        result, _ = self.run_import(source)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        blocks = json.loads(result.stdout)["blocks"]
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]["startMs"], 0)
        self.assertEqual(blocks[0]["durationMs"], 9000)


if __name__ == "__main__":
    unittest.main()
