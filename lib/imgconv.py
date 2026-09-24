#!/usr/bin/env python3
"""画像を PDF 埋め込み用に縮小・JPEG 化する補助スクリプト(hikarana.rb から呼ばれる)。

使い方: python3 imgconv.py <長辺px> <JPEG品質>   (stdin に [[src, dst], ...] の JSON)
出力  : stdout に [{"src":..., "dst":..., "ok":true/false, "error":...}, ...] の JSON

- 長辺が指定 px になるよう縮小する(元が小さければ拡大しない)。
- 透過があれば白背景に合成する(JPEG はアルファを持てない)。
- クロマサブサンプリングなし(4:4:4)で保存し、細い線や文字の色にじみを避ける。
"""
import json
import sys

try:
    from PIL import Image, ImageOps
except ImportError:
    print(json.dumps({"fatal": "Pillow (PIL) がインストールされていません"}))
    sys.exit(2)


def convert(src, dst, px, quality):
    im = Image.open(src)
    im.load()
    im = ImageOps.exif_transpose(im)
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.getchannel("A"))
        im = bg
    else:
        im = im.convert("RGB")
    w, h = im.size
    scale = px / max(w, h)
    if scale < 1:
        im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    im.save(dst, "JPEG", quality=quality, optimize=True, subsampling=0)


def main():
    px = int(sys.argv[1])
    quality = int(sys.argv[2])
    jobs = json.load(sys.stdin)
    results = []
    for src, dst in jobs:
        try:
            convert(src, dst, px, quality)
            results.append({"src": src, "dst": dst, "ok": True})
        except Exception as e:  # noqa: BLE001 - 1 件の失敗で全体を止めない
            results.append({"src": src, "dst": dst, "ok": False, "error": str(e)})
    json.dump(results, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
