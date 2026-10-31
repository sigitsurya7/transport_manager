#!/usr/bin/env python3
"""Tulis ulang length_m/width_m/height_m di content/vehicle_models.json dari model 3D.

Jalankan setelah mengubah geometri kendaraan di vehicles.py (test generator
menolak katalog yang dimensinya tidak cocok dengan model).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vehicles  # noqa: E402

path = os.path.abspath(vehicles.CONTENT)
text = open(path, encoding="utf-8").read()
catalog = json.loads(text)
for model in catalog["models"]:
    length, width, height = vehicles.dimensions(vehicles.build_vehicle(model, catalog)[0])
    start = text.index('{"id": "%s",' % model["id"])
    end = text.index("}", text.index('"price_idr":', start))
    chunk = re.sub(r', "length_m": [\d.]+, "width_m": [\d.]+, "height_m": [\d.]+', "", text[start:end])
    chunk = re.sub(r'("price_idr": \d+)', r'\1, "length_m": %s, "width_m": %s, "height_m": %s' % (length, width, height),
                   chunk)
    text = text[:start] + chunk + text[end:]
json.loads(text)
open(path, "w", encoding="utf-8", newline="\n").write(text)
print(f"Dimensi {len(catalog['models'])} model diperbarui.")
