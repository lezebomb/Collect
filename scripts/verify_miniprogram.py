"""Validate native page manifests, WXML and referenced event handlers offline."""
from pathlib import Path
import json
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1] / 'miniprogram'
for file in root.rglob('*.js'):
    subprocess.run(['node', '--check', str(file)], check=True, capture_output=True)
for file in root.rglob('*.json'):
    json.loads(file.read_text(encoding='utf-8'))
manifest = json.loads((root / 'app.json').read_text(encoding='utf-8'))
for page in manifest['pages']:
    js = (root / (page + '.js')).read_text(encoding='utf-8')
    wxml = (root / (page + '.wxml')).read_text(encoding='utf-8')
    # WXML accepts boolean attributes and raw JS operators inside {{ }}.
    xml = re.sub(r'{{.*?}}', lambda m: m[0].replace('&','&amp;').replace('<','&lt;'), wxml, flags=re.S)
    xml = re.sub(r'\s(scroll-x|lazy-load|password|wx:else)(?=\s|>)', r' \1="true"', xml)
    ET.fromstring('<root xmlns:wx="https://weixin.qq.com/wxml">' + xml + '</root>')
    for name in re.findall(r'(?:bind|catch)(?:tap|input|change|error|load)="([A-Za-z_][A-Za-z0-9_]*)"', wxml):
        assert re.search(r'\b' + re.escape(name) + r'\s*\(', js), f'{page}: missing handler {name}'
print(f'PASS: {len(manifest["pages"])} page manifests, JS syntax, WXML structure and event handlers.')
