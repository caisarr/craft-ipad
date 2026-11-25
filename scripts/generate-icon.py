#!/usr/bin/env python3
"""Generate a crisp 1024x1024 AppIcon PNG for Craft Suite using Python stdlib only."""

from pathlib import Path
import math
import struct
import zlib


SIZE = 1024


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def sd_rounded_box(px: float, py: float, cx: float, cy: float, hw: float, hh: float, r: float) -> float:
    dx = abs(px - cx) - (hw - r)
    dy = abs(py - cy) - (hh - r)
    qx = max(dx, 0.0)
    qy = max(dy, 0.0)
    return math.hypot(qx, qy) + min(max(dx, dy), 0.0) - r


def blend(dst: tuple[float, float, float], src: tuple[float, float, float], alpha: float) -> tuple[float, float, float]:
    a = clamp(alpha)
    return (
        dst[0] * (1.0 - a) + src[0] * a,
        dst[1] * (1.0 - a) + src[1] * a,
        dst[2] * (1.0 - a) + src[2] * a,
    )


def write_png(path: Path, width: int, height: int, rgb_rows: list[bytes]) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = b"".join(b"\x00" + row for row in rgb_rows)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB (no alpha for iOS AppIcon)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, level=9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def render_icon() -> list[bytes]:
    rows: list[bytes] = []

    # Precompute rotated card helper
    def card_sdf(x: float, y: float, cx: float, cy: float, hw: float, hh: float, r: float, angle_deg: float) -> tuple[float, float, float]:
        rad = math.radians(angle_deg)
        c, s = math.cos(rad), math.sin(rad)
        dx, dy = x - cx, y - cy
        lx = dx * c + dy * s
        ly = -dx * s + dy * c
        return sd_rounded_box(lx, ly, 0.0, 0.0, hw, hh, r), lx, ly

    for y in range(SIZE):
        row = bytearray(SIZE * 3)
        ny = y / (SIZE - 1)
        for x in range(SIZE):
            nx = x / (SIZE - 1)

            # Deep slate gradient background
            grad = 0.65 * ny + 0.35 * nx
            r = 15.0 + 18.0 * grad
            g = 23.0 + 24.0 * grad
            b = 42.0 + 38.0 * grad

            # Soft ambient radial glow near center-top
            dist_glow = math.hypot(x - 512.0, y - 430.0) / 560.0
            glow = max(0.0, 1.0 - dist_glow) ** 2.0
            col = (r + 22.0 * glow, g + 34.0 * glow, b + 58.0 * glow)

            # Card 1 (Back-left): GridCraft Emerald
            d1, lx1, ly1 = card_sdf(x, y, 360.0, 520.0, 170.0, 225.0, 38.0, -14.0)
            sh1 = 1.0 - smoothstep(-6.0, 34.0, d1 + 14.0)
            if sh1 > 0.0:
                col = blend(col, (5.0, 10.0, 20.0), 0.38 * sh1)
            a1 = 1.0 - smoothstep(-1.5, 1.5, d1)
            if a1 > 0.0:
                t1 = clamp((ly1 + 225.0) / 450.0)
                c1 = (16.0 + 10.0 * t1, 185.0 - 30.0 * t1, 129.0 - 20.0 * t1)
                # Subtle spreadsheet grid lines inside GridCraft card
                gx = abs((lx1 + 90.0) % 60.0 - 30.0)
                gy = abs((ly1 + 120.0) % 52.0 - 26.0)
                if -125 < lx1 < 125 and -140 < ly1 < 150 and (gx > 27.5 or gy > 23.5):
                    c1 = blend(c1, (236.0, 253.0, 245.0), 0.28)
                col = blend(col, c1, a1)

            # Card 2 (Back-right): WordCraft Sky Blue
            d2, lx2, ly2 = card_sdf(x, y, 664.0, 520.0, 170.0, 225.0, 38.0, 14.0)
            sh2 = 1.0 - smoothstep(-6.0, 34.0, d2 + 14.0)
            if sh2 > 0.0:
                col = blend(col, (5.0, 10.0, 20.0), 0.38 * sh2)
            a2 = 1.0 - smoothstep(-1.5, 1.5, d2)
            if a2 > 0.0:
                t2 = clamp((ly2 + 225.0) / 450.0)
                c2 = (59.0 - 15.0 * t2, 130.0 - 20.0 * t2, 246.0 - 20.0 * t2)
                # Subtle document text bars inside WordCraft card
                for bar_y, bar_w in [(-95.0, 95.0), (-45.0, 110.0), (5.0, 110.0), (55.0, 78.0)]:
                    if abs(ly2 - bar_y) < 9.0 and abs(lx2) < bar_w:
                        c2 = blend(c2, (239.0, 246.0, 255.0), 0.42)
                col = blend(col, c2, a2)

            # Card 3 (Center-front): PdfCraft Coral Red
            d3, lx3, ly3 = card_sdf(x, y, 512.0, 500.0, 185.0, 242.0, 42.0, 0.0)
            sh3 = 1.0 - smoothstep(-8.0, 42.0, d3 + 18.0)
            if sh3 > 0.0:
                col = blend(col, (4.0, 8.0, 16.0), 0.48 * sh3)
            a3 = 1.0 - smoothstep(-1.5, 1.5, d3)
            if a3 > 0.0:
                t3 = clamp((ly3 + 242.0) / 484.0)
                c3 = (244.0 - 22.0 * t3, 63.0 - 10.0 * t3, 94.0 + 14.0 * t3)
                # Inner crisp white emblem ring + diamond
                ring_d = abs(math.hypot(lx3, ly3 + 10.0) - 68.0) - 11.0
                if ring_d < 1.5:
                    c3 = blend(c3, (255.0, 245.0, 247.0), 1.0 - smoothstep(-1.5, 1.5, ring_d))
                diam_d = (abs(lx3) + abs(ly3 + 10.0)) * 0.7071 - 24.0
                if diam_d < 1.5:
                    c3 = blend(c3, (255.0, 245.0, 247.0), 1.0 - smoothstep(-1.5, 1.5, diam_d))
                # Top-edge subtle highlight
                if ly3 < -220.0:
                    c3 = blend(c3, (255.0, 255.0, 255.0), 0.14)
                col = blend(col, c3, a3)

            idx = x * 3
            row[idx] = int(clamp(col[0], 0.0, 255.0))
            row[idx + 1] = int(clamp(col[1], 0.0, 255.0))
            row[idx + 2] = int(clamp(col[2], 0.0, 255.0))
        rows.append(bytes(row))
    return rows


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    out = root / "ios" / "CraftSuite" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    rows = render_icon()
    write_png(out, SIZE, SIZE, rows)
    print(f"Generated {out} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
