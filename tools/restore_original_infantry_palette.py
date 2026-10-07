#!/usr/bin/env python3
"""Restore authored clothes and ink. Restrict owner ink to existing insignia.
Geometry, all role tools, pose-specific drawing and original contours are intact.
"""
from pathlib import Path
import copy
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
NS='{http://www.w3.org/2000/svg}'
ET.register_namespace('',NS[1:-1])
def main():
 count=0
 for source in sorted((ROOT/'assets/cards/original_infantry_source').glob('*.svg')):
  picture=ET.fromstring(source.read_text())
  mask=copy.deepcopy(picture)
  # Authored golden insignia, shoulder patch and helmet flash only.
  for el in mask.iter():
   if el.tag in [NS+'defs',NS+'clipPath']:continue
   for attr in ['fill','stroke']:
    value=el.get(attr)
    if value not in [None,'none']:
     el.set(attr,'#ffffff' if value.lower()=='#e7ad42' else '#000000')
  out=ROOT/'assets/cards'/source.name
  out.write_text(ET.tostring(picture,encoding='unicode'))
  out.with_name(out.stem+'_identity.svg').write_text(ET.tostring(mask,encoding='unicode'))
  count+=1
 print('Restored original infantry drawings and small insignia masks:',count)
if __name__=='__main__':main()
