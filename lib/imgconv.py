#!/usr/bin/env python3
"""画像を PDF 埋め込み用に縮小・JPEG 化する補助スクリプト(hikarana.rb から呼ばれる)。

使い方: python3 imgconv.py <長辺px> <JPEG品質>   (stdin に [[src, dst], ...] の JSON)
出力  : stdout に [{"src":..., "dst":..., "ok":true/false, "error":...}, ...] の JSON

- 長辺が指定 px になるよう縮小する(元が小さければ拡大しない)。
- 元が既に長辺 px 以下の JPEG なら再エンコードせずそのままコピーする。
- 透過があれば白背景に合成する(JPEG はアルファを持てない)。
- クロマサブサンプリングなし(4:4:4)で保存し、細い線や文字の色にじみを避ける。
"""
import json
import shutil
import sys

try:
    from PIL import Image, ImageOps
except ImportError:
    print(json.dumps({"fatal": "Pillow (PIL) がインストールされていません"}))
    sys.exit(2)


def passthrough(im, px):
    """元画像がそのまま使える JPEG か(長辺 px 以下、透過なし、EXIF の回転なし)。"""
    if im.format != "JPEG" or max(im.size) > px:
        return False
    if im.mode not in ("RGB", "L"):
        return False
    return im.getexif().get(0x0112, 1) == 1


def convert(src, dst, px, quality):
    im = Image.open(src)
    if passthrough(im, px):
        shutil.copyfile(src, dst)
        return True
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
    return False


def main():
    px = int(sys.argv[1])
    quality = int(sys.argv[2])
    jobs = json.load(sys.stdin)
    results = []
    for src, dst in jobs:
        try:
            copied = convert(src, dst, px, quality)
            results.append({"src": src, "dst": dst, "ok": True, "copied": copied})
        except Exception as e:  # noqa: BLE001 - 1 件の失敗で全体を止めない
            results.append({"src": src, "dst": dst, "ok": False, "error": str(e)})
    json.dump(results, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
