"""Verify and show the two normalized images captured from real RTL writes."""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]


def main():
    font = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 22)
    sheet = Image.new('RGB', (1280, 544), '#eaf2ef')
    draw = ImageDraw.Draw(sheet)
    for index, (name, title) in enumerate((
            ('normal', '源图320×240 → FPGA放大至640×480'),
            ('safety', '源图800×600 → FPGA缩小至640×480'))):
        capture = Image.open(ROOT / f'sim/results/scale_{name}.ppm').convert('RGB')
        reference = Image.open(ROOT / f'assets/scale_demo/{name}_scaled_reference.png').convert('RGB')
        if capture.size != (640, 480) or ImageChops.difference(capture, reference).getbbox():
            raise RuntimeError('RTL/reference scaled pixels differ: ' + name)
        capture.save(ROOT / f'sim/results/scale_{name}.png')
        draw.text((index * 640 + 18, 16), title, font=font, fill='#075333')
        sheet.paste(capture, (index * 640, 64))
    sheet.save(ROOT / 'sim/results/scale_demo_preview.png')
    print('PASS actual RTL scaling captures match reference pixels; preview saved')


if __name__ == '__main__':
    main()
