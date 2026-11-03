"""Convert actual RTL raster captures into reviewable images, without redrawing UI."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'sim/results'
CAPTURES = [
    ('map_open', '校园疏散 / 单区域危险'),
    ('map_closed', '全部区域危险 / 无可用出口'),
    ('health', '当前状态 / 事件用时'),
    ('history', '最近四条易失记录'),
    ('drill', '疏散演练场景'),
    ('mall_map', '商场疏散图'),
    ('mall_fire', '商场火情'),
    ('mall_crowd', '商场人员拥挤'),
    ('mall_power', '商场停电故障'),
    ('mall_escalator', '商场扶梯故障'),
    ('publish_confirm', '发布二次确认'),
    ('clear_confirm', '解除二次确认'),
    ('drill_report', '疏散演练评估报告'),
    ('route_pending', '真实场景路线变更待确认'),
    ('map_west', '左半区危险 / 推荐出口二'),
    ('map_east', '右半区危险 / 推荐出口一'),
    ('campus_fire', '校园火情 / 实际BMP与音频条'),
    ('campus_quake', '校园地震 / 实际BMP与音频条'),
    ('drill_flood', '演练洪涝 / 实际BMP与音频条'),
    ('drill_evac', '演练疏散 / 实际BMP与音频条'),
]


def main():
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 22)
    sheet = Image.new('RGB', (640 * 3, 520 * ((len(CAPTURES)+2)//3)), '#e8edf3')
    draw = ImageDraw.Draw(sheet)
    for index, (name, title) in enumerate(CAPTURES):
        source = OUT / (name + '.ppm')
        raster = Image.open(source).convert('RGB')
        if raster.size != (640, 480):
            raise ValueError('Unexpected capture dimensions: ' + str(source))
        raster.save(OUT / (name + '.png'))
        left, top = (index % 3) * 640, (index // 3) * 520
        draw.text((left + 12, top + 5), title, fill='#10243c', font=font)
        sheet.paste(raster, (left, top + 40))
    target = OUT / 'safety_preview.png'
    sheet.save(target)
    print('Rendered actual RTL captures:', target)


if __name__ == '__main__':
    main()
