"""Generate the VR-OS icon from original geometric artwork; no external assets."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

folder = Path(__file__).resolve().parents[1] / 'VROS/VR_OS_Icons.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
icon = Image.new('RGB', (1024, 1024), '#14171C')
draw = ImageDraw.Draw(icon)
draw.rounded_rectangle((150, 305, 874, 719), radius=140, fill='#252A31', outline='#F2F2F2', width=30)
draw.rounded_rectangle((230, 398, 452, 604), radius=66, fill='#FF9544')
draw.rounded_rectangle((572, 398, 794, 604), radius=66, fill='#FF9544')
draw.arc((440, 420, 584, 535), 185, 355, fill='#F2F2F2', width=27)
draw.polygon([(450, 735), (481, 662), (512, 646), (543, 662), (574, 735)], fill='#14171C')
images = []
for size in [20, 29, 40, 60]:
    for scale in [2, 3]:
        name = f'Icon-{size}@{scale}x.png'
        icon.resize((size * scale, size * scale), Image.Resampling.LANCZOS).save(folder / name)
        images.append({'idiom': 'iphone', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': name})
icon.save(folder / 'Icon-1024.png')
images.append({'idiom': 'ios-marketing', 'size': '1024x1024', 'scale': '1x', 'filename': 'Icon-1024.png'})
(folder / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
