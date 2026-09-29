"""Compile the real Pro compositor/fonts under ASan+UBSan and replay real art."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import zlib

HERE = Path(__file__).resolve().parent
NATIVE = HERE.parent / "main/ui/habitat"
GENERATED = HERE.parents[1] / "prototype/pro-companion/generated"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", action="store_true", help="After sanitized checks, measure CPU-time raster of real-art720px scenes")
    parser.add_argument("--baseline", type=Path, help="Compare benchmarks against this previous pro_canvas.c implementation")
    args = parser.parse_args()
    manifest = json.loads((GENERATED / "manifest.json").read_text())
    pack = (GENERATED / "pro_art.pack").read_bytes()
    assert hashlib.sha256(pack).hexdigest() == manifest["sha256"]
    blocks = {b["name"]: b for b in manifest["blocks"]}
    with tempfile.TemporaryDirectory(prefix="harness-pro-canvas-") as directory:
        out = Path(directory)
        fixture_paths = []
        # Exercise the real cropped layers, padded to the primitive fixtures'
        # square geometry. Full layered composition is covered by test_pro_visual.
        for name, size in (("scene_meadow", 720), ("tim_350_rear_0_0", 350),
                           ("tim_350_rear_0_2", 350), ("tim_160_speech_warm_4", 160)):
            block = blocks[name]
            raw = zlib.decompress(pack[block["offset"]:block["offset"]+block["length"]])
            assert len(raw) == block["raw_length"]
            assert hashlib.sha256(raw).hexdigest() == block["sha256"]
            width, height = block["width"], block["height"]
            x, y = block["x"], block["y"]
            assert 0 <= x < size and 0 <= y < size
            assert x + width <= size and y + height <= size
            assert len(raw) == width * height * (3 if block["alpha"] else 2)
            if block["alpha"]:
                square = bytearray(size * size * 3)
                for row in range(height):
                    src = row * width
                    dst = (y + row) * size + x
                    square[dst * 2:(dst + width) * 2] = raw[src * 2:(src + width) * 2]
                    square[size * size * 2 + dst:size * size * 2 + dst + width] = \
                        raw[width * height * 2 + src:width * height * 2 + src + width]
                raw = bytes(square)
            else:
                assert width == height == size and x == y == 0
            path = out / (name + ".raw")
            path.write_bytes(raw)
            fixture_paths.append(str(path))
        binary = out / "test_pro_canvas"
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                        "-fsanitize=" + os.environ.get("SANITIZERS", "address,undefined,bounds"),
                        "-fno-omit-frame-pointer", "-DHT_FACE_PX=720", "-DDEVICE_PRO_COMPANION=1",
                        "-I", str(NATIVE), str(HERE / "test_pro_canvas.c"),
                        str(NATIVE / "pro_canvas.c"), str(NATIVE / "terminal.c"), str(NATIVE / "fonts.c"),
                        str(GENERATED / "pro_fonts.c"), "-o", str(binary)], check=True)
        env = dict(os.environ)
        # Apple ASan has no LeakSanitizer; bounds and lifetime checks stay enabled.
        env.setdefault("ASAN_OPTIONS", ("detect_leaks=0:" if sys.platform == "darwin" else "detect_leaks=1:") + "abort_on_error=1")
        env.setdefault("UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1")
        subprocess.run([str(binary), *fixture_paths], env=env, check=True)
        if args.benchmark or args.baseline:
            reports = {}
            for label, canvas in (("baseline", args.baseline), ("current", NATIVE / "pro_canvas.c")):
                if canvas is None:
                    continue
                bench = out / ("bench_" + label)
                subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                                "-DHT_FACE_PX=720", "-DDEVICE_PRO_COMPANION=1", "-I", str(NATIVE),
                                str(HERE / "test_pro_canvas.c"), str(canvas), str(NATIVE / "terminal.c"),
                                str(NATIVE / "fonts.c"), str(GENERATED / "pro_fonts.c"), "-o", str(bench)], check=True)
                result = subprocess.run([str(bench), *fixture_paths, "--benchmark"], text=True, capture_output=True, check=True)
                reports[label] = {row["scene"]: row for row in
                                  (json.loads(line[6:]) for line in result.stdout.splitlines() if line.startswith("BENCH "))}
                print(json.dumps({"benchmark": label, "results": list(reports[label].values()),
                                  "scope": "host primitive CPU time with padded real art layers; 300 renders per batch, median 5 batches, 24-line strips; excludes full daemon composition, decode, DMA, USB"}))
            if "baseline" in reports:
                comparison = []
                for scene, after in reports["current"].items():
                    before = reports["baseline"][scene]
                    assert before["hash"] == after["hash"], f"Output changed in {scene}"
                    comparison.append({"scene": scene, "baseline_us": before["median_us"], "current_us": after["median_us"],
                                       "speedup": round(before["median_us"] / after["median_us"], 3), "pixels_identical": True})
                print(json.dumps({"comparison": comparison}))


if __name__ == "__main__":
    main()
