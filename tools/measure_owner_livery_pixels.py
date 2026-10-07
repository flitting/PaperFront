"""Measure blue ink in the real PaperWorld screenshots; never alters images."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1]/'artifacts/rts_revision'
rows=[]
for backend in ('forward_plus','gl_compatibility'):
 for pose in ('front','side','backlit'):
  path=root/f'owner_canon_{pose}_{backend}.png'
  pixels=np.asarray(Image.open(path).convert('RGB'),dtype=float)
  mask=(pixels[:,:,2]-pixels[:,:,0]>70)&(pixels[:,:,2]-pixels[:,:,1]>20)&(pixels[:,:,1]>55)
  blue=pixels[mask]
  assert len(blue)>1000,(path,'insufficient visible owner ink')
  rows.append({'file':path.name,'blue_pixels':int(mask.sum()),'mean_blue_rgb':np.round(blue.mean(axis=0),1).tolist(),'mean_blue_value':round(float(blue.max(axis=1).mean()/255),3)})
for backend in ('forward_plus','gl_compatibility'):
 values=[r['mean_blue_value'] for r in rows if backend+'.png' in r['file']]
 assert max(values)-min(values)<.015,(backend,'paper pigment changes under front/side/backlight')
(root/'owner_live_pixel_report.json').write_text(json.dumps({'measurement':'Blue pixels: B-R>70, B-G>20, G>55; screenshots from actual PaperWorld batching and game lighting; no edits','source_images':rows},indent=2)+'\n')
print('OWNER_LIVE_PIXEL_CHECKS',json.dumps(rows))
