from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[2]
ICON_DIR = ROOT / "assets/icons"
SIZE = 1024

im = Image.new("RGB", (SIZE, SIZE))
d = ImageDraw.Draw(im)
for y in range(SIZE):
    t = y / (SIZE - 1)
    d.line((0, y, SIZE, y), fill=(int(7 + 9*t), int(21 + 11*t), int(39 + 17*t)))
# Textless open-book emblem with a vault-like spine marker.
d.polygon([(512,280),(512,680),(470,652),(420,630),(360,614),(290,610),(228,620),(228,286),(298,265),(370,267),(438,284)], fill=(49,220,245))
d.polygon([(512,280),(512,680),(554,652),(604,630),(664,614),(734,610),(796,620),(796,286),(726,265),(654,267),(586,284)], fill=(27,145,231))
d.polygon([(270,325),(340,309),(432,326),(476,346),(476,588),(420,563),(350,548),(270,551)], fill=(10,29,49))
d.polygon([(754,325),(684,309),(592,326),(548,346),(548,588),(604,563),(674,548),(754,551)], fill=(10,29,49))
for y in (382,434,486):
    d.line([(302,y),(386,y-7),(442,y+7)], fill=(89,227,247), width=13)
    d.line([(722,y),(638,y-7),(582,y+7)], fill=(89,227,247), width=13)
d.line([(512,298),(512,662)], fill=(225,255,255), width=18)
d.ellipse((463,704,561,802), fill=(240,255,255))
d.ellipse((490,731,534,775), fill=(20,129,218))

source = ICON_DIR / "panovault_1024.png"
im.save(source, optimize=True)
for density, size in {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}.items():
    out = ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    im.resize((size,size),Image.Resampling.LANCZOS).save(out,optimize=True)
ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for entry in json.loads((ios/"Contents.json").read_text())["images"]:
    filename = entry.get("filename")
    if not filename: continue
    width = round(float(entry["size"].split("x")[0]) * float(entry["scale"].removesuffix("x")))
    im.resize((width,width),Image.Resampling.LANCZOS).save(ios/filename,optimize=True)
print(f"Generated Android and iOS icon variants from {source}")
