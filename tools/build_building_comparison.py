#!/usr/bin/env python3
"""Compose authored faction art next to equal-camera world-scale 3D captures.

Reference panels preserve a single source-pixel scale; model renders never crop
or independently normalize their object bounds. Before/after share every camera
parameter and include the existing tank and original paper infantry.
"""
from pathlib import Path
import argparse
import csv
import json
import statistics
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = '/usr/share/fonts/truetype/arphic/uming.ttc'
FONTS = {n: ImageFont.truetype(FONT, n) for n in (20, 24, 30, 38)}
REFERENCE_PANELS = {
    'kestrel_hq': (12, 258, 294, 460),
    'kestrel_barracks': (300, 258, 580, 460),
    'kestrel_power': (585, 258, 860, 460),
    'kestrel_refinery': (863, 258, 1142, 460),
    'kestrel_command': (300, 472, 580, 681),
    'kestrel_tech': (585, 472, 860, 681),
    'kestrel_airfield': (863, 472, 1142, 681),
    'kestrel_outpost': (1145, 472, 1436, 681),
    'kestrel_tower': (1145, 472, 1436, 681),
    'kestrel_factory': (1145, 258, 1436, 460),
    'kestrel_repair': (12, 472, 294, 681),
    'rivet_hq': (15, 257, 246, 485),
    'rivet_outpost': (250, 257, 477, 485),
    'rivet_barracks': (480, 257, 709, 485),
    'rivet_power': (714, 257, 939, 485),
    'rivet_refinery': (942, 257, 1166, 485),
    'rivet_command': (480, 489, 709, 716),
    'rivet_tech': (714, 489, 939, 716),
    'rivet_airfield': (942, 489, 1166, 716),
    'rivet_tower': (250, 257, 477, 485),
    'rivet_factory': (15, 489, 246, 716),
    'rivet_repair': (250, 489, 477, 716),
}
ROLE_TITLES = {'hq': '总部', 'outpost': '前线基地', 'power': '发电站', 'refinery': '精炼厂', 'barracks': '兵营', 'factory': '战车工厂', 'tower': '守备塔', 'tech': '研究所', 'repair': '工程维修站', 'command': '指挥中心', 'airfield': '机场'}
BG, INK, DIVIDER = '#f1e4c6', '#382a22', '#c4ae83'


def text(draw, xy, value, size=24):
    draw.text(xy, value, fill=INK, font=FONTS[size])


def make_row(model_id, captures, refs, before, after):
    # Keep all model renders at the same 0.60 pixel scale, irrespective of art.
    row = Image.new('RGB', (2300, 652), BG)
    draw = ImageDraw.Draw(row)
    faction, role = model_id.split('_', 1)
    text(draw, (24, 12), ('正典军团' if faction == 'kestrel' else '重锤军团')+' / '+ROLE_TITLES[role], 30)
    for x, label in ((24, '原稿前线基地局部（无单独守备塔）' if role == 'tower' else '原设计图局部'), (800, '修复前 / 同世界尺度'), (1552, '修复后 / 同世界尺度')):
        text(draw, (x, 54), label, 24)
    panel = refs[faction].crop(REFERENCE_PANELS[model_id])
    # A single 2x scale preserves cross-role proportions in the reference sheet.
    panel = panel.resize((panel.width*2, panel.height*2), Image.Resampling.LANCZOS)
    row.paste(panel, (24+(744-panel.width)//2, 94+(540-panel.height)//2))
    for phase, x in [('before', 800), ('after', 1552)]:
        path = captures/phase/(model_id+'_scale.png')
        shot = Image.open(path).convert('RGB')
        if shot.size != (1200, 900):
            raise ValueError(f'Unexpected capture dimensions: {path}: {shot.size}')
        shot = shot.resize((720, 540), Image.Resampling.LANCZOS)
        row.paste(shot, (x, 94))
        measurement = (before if phase == 'before' else after)['models'][model_id]
        metrics = f"实体占地 {measurement['mass_coverage']:.1%} · 净实体 {measurement['mass_volume_above_plinth']:.2f} u³"
        text(draw, (x+10, 610), metrics, 20)
    for x in (781, 1534): draw.line((x, 45, x, 644), fill=DIVIDER, width=2)
    return row


def compose(roles, captures, destination):
    before = json.loads((captures/'before/scale_capture_manifest.json').read_text())
    after = json.loads((captures/'after/scale_capture_manifest.json').read_text())
    for field in ('viewport', 'camera_projection', 'camera_vertical_world_span', 'pitch', 'yaw', 'building_position', 'tank_position', 'paper_position'):
        if before[field] != after[field]: raise ValueError(f'Camera/scale mismatch: {field}')
    refs = {f: Image.open(ROOT/'docs/派系设定'/n).convert('RGB') for f,n in [('kestrel','正典军团.png'),('rivet','重锤军团.png')]}
    rows = [make_row(f+'_'+a, captures, refs, before, after) for a in roles for f in ['kestrel','rivet']]
    sheet = Image.new('RGB', (2300, 125+len(rows)*652), BG)
    draw = ImageDraw.Draw(sheet)
    text(draw, (24, 14), '建筑实心体量 / 原图 · 修复前 · 修复后', 38)
    text(draw, (24, 65), '前后固定30°俯角、22°侧转、9世界单位镜头跨度；每格1单位，坦克与原纸兵保持实际游戏尺寸。', 24)
    text(draw, (24, 95), '参考图缺少绝对尺度，按原稿统一2倍像素显示；实体统计排除底板，使用真实三角网格的并集体积。', 20)
    for i,row in enumerate(rows): sheet.paste(row, (0,125+i*652))
    sheet.save(destination)
    return str(destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--captures', type=Path, default=ROOT/'artifacts/building_repair/reference_review_v1')
    parser.add_argument('--output', type=Path, default=ROOT/'artifacts/building_repair/comparisons')
    parser.add_argument('--all', action='store_true', help='Compose all 22 buildings after a --all capture batch')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    roles = list(ROLE_TITLES) if args.all else ['hq','factory','repair']
    results = [compose([role], args.captures, args.output/(role+'_comparison.png')) for role in roles]
    results.append(compose(roles, args.captures, args.output/('all_22_buildings.png' if args.all else 'six_representatives.png')))
    before = json.loads((args.captures/'before/scale_capture_manifest.json').read_text())
    after = json.loads((args.captures/'after/scale_capture_manifest.json').read_text())
    rows = []
    for model_id in sorted(after['models']):
        old, new = before['models'][model_id], after['models'][model_id]
        rows.append({'model':model_id, 'mass_coverage_before':old['mass_coverage'], 'mass_coverage_after':new['mass_coverage'], 'mass_volume_before':old['mass_volume_above_plinth'], 'mass_volume_after':new['mass_volume_above_plinth'], 'volume_factor':new['mass_volume_above_plinth']/max(.001,old['mass_volume_above_plinth']), 'actual_bounds_after':new['actual_aabb']})
    summary = {'before_source_sha256':before['source_sha256'], 'after_source_sha256':after['source_sha256'], 'comparison_images':results, 'models':rows, 'average_coverage_before':statistics.mean(r['mass_coverage_before'] for r in rows), 'average_coverage_after':statistics.mean(r['mass_coverage_after'] for r in rows), 'median_volume_factor':statistics.median(r['volume_factor'] for r in rows), 'total_mass_volume_before':sum(r['mass_volume_before'] for r in rows), 'total_mass_volume_after':sum(r['mass_volume_after'] for r in rows), 'units':'world units; u³ for volume'}
    (args.output/'comparison_statistics.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    with (args.output/'comparison_statistics.csv').open('w',newline='') as file:
        writer = csv.DictWriter(file,fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({'comparison_images':results, 'statistics':str(args.output/'comparison_statistics.json')}, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
