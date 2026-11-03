"""Prepare two approved mixed-size daily BMPs without changing emergency media.

Pillow is used only to prepare the TF assets and reference previews. The board
performs the actual nearest-neighbour scaling in bmp_scale_decoder.v.
"""
from functools import reduce
from hashlib import sha256
import json
from pathlib import Path
import re
import struct

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'assets/scale_demo'
OUT = ROOT / 'TF_CARD_ROOT'
NAMES = ('NORMAL.BMP', 'SAFETY.BMP', 'FIRE.BMP', 'QUAKE.BMP', 'FLOOD.BMP', 'EVAC.BMP')
DEMO = {
    'NORMAL.BMP': ((320, 240), '320x240 -> 640x480', '090aec6da2ffab9c5b1e3a8c54ca6a5ef0e9ccef9096914dd7793a5ab1307f15'),
    'SAFETY.BMP': ((800, 600), '800x600 -> 640x480', '1d7d3f76be131f36dfb11b39b7485cd62aac8f52a1abc0004ddd4f3d94a7a95f'),
}


def digest(data):
    return sha256(data).hexdigest()


def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', size)


def normalized(image):
    """Floor-sample rows in BMP storage order, then restore display order.

Pillow writes positive-height (bottom-up) BMPs. Resampling happens before the
frame loader reverses row addresses, so the vertical sample phase follows the
bottom row, as it does in the existing hardware decoder.
"""
    width, height = image.size
    pixels = image.load()
    result = Image.new('RGB', (640, 480))
    result.putdata([pixels[x * width // 640, height - 1 - (479 - y) * height // 480]
                    for y in range(480) for x in range(640)])
    return result


def main():
    approved_path = ROOT / 'config/approved_tf_assets.json'
    if approved_path.is_file():
        previous = json.loads(approved_path.read_text(encoding='utf-8'))['assets']
    else:
        release = json.loads((ROOT / 'release_manifest_v2.json').read_text(encoding='utf-8'))
        previous = release.get('assets', release.get('assets_unchanged_from_v1'))
    for name, expected in previous.items():
        if name not in DEMO and digest((OUT / name).read_bytes()) != expected['sha256']:
            raise RuntimeError('Unrelated approved media changed: ' + name)

    for name, (size, dimension_label, expected_sha) in DEMO.items():
        source = SOURCES / name
        if digest(source.read_bytes()) != expected_sha:
            raise RuntimeError('Original daily source changed: ' + str(source))
        with Image.open(source) as original:
            canvas = original.convert('RGB')
        draw = ImageDraw.Draw(canvas)
        # Keep markers inside the visible image area between top OSD and ticker.
        draw.rectangle((20, 46, 619, 429), outline='#B8FFE5', width=1)
        for x, y, dx, dy in ((20, 46, 1, 1), (619, 46, -1, 1),
                             (20, 429, 1, -1), (619, 429, -1, -1)):
            draw.line((x, y, x + dx * 16, y), fill='#FFEF68', width=3)
            draw.line((x, y, x, y + dy * 16), fill='#FFEF68', width=3)
        # Keep the scale annotation concise and outside the icon/content areas.
        draw.text((44, 57), dimension_label, font=font(19), fill='#FFEF68',
                  stroke_width=2, stroke_fill='#075333')
        image = canvas.resize(size, Image.Resampling.LANCZOS)
        image.save(OUT / name, format='BMP')
        normalized(image).save(SOURCES / (Path(name).stem.lower() + '_scaled_reference.png'))

    assets = {}
    for path in sorted(OUT.iterdir()):
        if path.suffix.upper() not in {'.BMP', '.PCM'}:
            continue
        data = path.read_bytes()
        info = {'bytes': len(data), 'sha256': digest(data),
                'xor8': f'{reduce(lambda a, b: a ^ b, data, 0):02x}'}
        if path.suffix.upper() == '.BMP':
            width, height, planes, bpp, compression = struct.unpack_from('<iiHHI', data, 18)
            expected = DEMO[path.name][0] if path.name in DEMO else (640, 480)
            if (data[:2] != b'BM' or (width, abs(height)) != expected or
                    (planes, bpp, compression) != (1, 24, 0)):
                raise RuntimeError('Unsupported demonstration BMP: ' + str(path))
            info.update(width=width, height=abs(height), bpp=bpp, compression=compression,
                        normalized_width=640, normalized_height=480)
        assets[path.name] = info
    if len(assets) != 10:
        raise RuntimeError('Expected six BMP and four PCM assets')
    approved_path.write_text(json.dumps({
        'variant': 'mixed-size daily scaling demonstration',
        'modified_from_original': list(DEMO),
        'assets': assets,
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    # Mechanical regeneration of only the six content signatures; no RTL
    # function, bypass or media-integrity policy is changed.
    rtl_path = ROOT / 'src/media_ingest_pipeline.v'
    rtl = rtl_path.read_text(encoding='utf-8')
    for index, name in enumerate(NAMES):
        key = str(index) if index < 5 else 'default'
        pattern = rf"({key}:expected_image_crc=8'h)[0-9a-fA-F]{{2}}"
        rtl, count = re.subn(pattern, lambda m: m[1] + assets[name]['xor8'], rtl)
        if count != 1:
            raise RuntimeError('Image CRC constant not found: ' + name)
    rtl_path.write_text(rtl, encoding='utf-8')
    print('Prepared mixed-size BMPs and six approved image signatures:')
    for name in NAMES:
        info = assets[name]
        print(name, f"{info['width']}x{info['height']}", 'XOR8=' + info['xor8'])


if __name__ == '__main__':
    main()
