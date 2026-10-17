#!/usr/bin/env python3
"""Write the power-up frame buffer image for rtl/framebuffer.sv.

Output: $readmemh file, one 6-bit RGB222 pixel {r1 r0 g1 g0 b1 b0} per line,
row-major (address y*W + x).

Without --image: test image of all 64 colours as an 8x8 grid of cells
(colour index = row*8 + col), with a 1-pixel white border around the frame.
With --image: the picture is scaled to WxH and reduced to the 64 RGB222
colours with Floyd-Steinberg dithering (needs Pillow).
"""
import argparse

LEVELS = (0x00, 0x55, 0xAA, 0xFF)   # 2-bit channel -> 8-bit, as the hardware expands it


def test_image(w, h):
    pix = []
    for y in range(h):
        for x in range(w):
            if x in (0, w - 1) or y in (0, h - 1):
                pix.append(0x3F)
            else:
                pix.append((y * 8 // h) * 8 + x * 8 // w)
    return pix


def convert(path, w, h, dither):
    from PIL import Image

    pal = Image.new("P", (1, 1))
    colours = [c for i in range(64) for c in (LEVELS[i >> 4], LEVELS[(i >> 2) & 3], LEVELS[i & 3])]
    pal.putpalette(colours + colours[:3] * (256 - 64))
    img = Image.open(path).convert("RGB").resize((w, h), Image.Resampling.LANCZOS)
    img = img.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE)
    return [(r // 85) << 4 | (g // 85) << 2 | b // 85 for r, g, b in img.convert("RGB").getdata()]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="output .hex file")
    ap.add_argument("--image", help="picture to convert instead of the test image")
    ap.add_argument("--width", type=int, default=800)
    ap.add_argument("--height", type=int, default=600)
    ap.add_argument("--no-dither", action="store_true", help="nearest colour instead of dithering")
    args = ap.parse_args()

    if args.image:
        pix = convert(args.image, args.width, args.height, not args.no_dither)
    else:
        pix = test_image(args.width, args.height)
    with open(args.out, "w") as f:
        f.writelines(f"{p:02x}\n" for p in pix)


if __name__ == "__main__":
    main()
