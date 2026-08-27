#!/usr/bin/env python3
"""
Converts the two base64-packed .data.json assets into (meta JSON + raw binary) pairs.

WHY: foodEmbeddings.data.json is a 3.8 MB JSON file whose payload is a single
3,655,680-character base64 string. Parsing that as JSON and decoding it in-process on
every cold start is pure waste when the bytes never change. The numbers are untouched -
this only changes the container, exactly as the porting brief allows.

The Swift side memory-maps the .bin. Phase 3 asserts the resulting cosines match the TS
engine's to 1e-9, so the container swap is proven, not assumed.
"""
import base64, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', '..', 'app', 'engine')
DST = os.path.join(HERE, '..', 'Sources', 'SmartSwapsKit', 'Resources')

def convert(src_name, bin_name, meta_name, bytes_per):
    with open(os.path.join(SRC, src_name)) as f:
        d = json.load(f)
    raw = base64.b64decode(d.pop('q'))
    n = d['count'] * bytes_per(d)
    assert len(raw) == n, f'{src_name}: decoded {len(raw)} bytes, expected {n}'
    with open(os.path.join(DST, bin_name), 'wb') as f:
        f.write(raw)
    with open(os.path.join(DST, meta_name), 'w') as f:
        json.dump(d, f, separators=(',', ':'))
    print(f'{src_name}: {len(raw)} bytes -> {bin_name}, meta -> {meta_name}')

convert('foodEmbeddings.data.json', 'foodEmbeddings.bin', 'foodEmbeddings.meta.json', lambda d: d['dim'])
convert('foodAttributes.data.json', 'foodAttributes.bin', 'foodAttributes.meta.json', lambda d: d['bytesPerFood'])
