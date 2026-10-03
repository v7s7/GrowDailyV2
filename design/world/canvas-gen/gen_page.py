"""Generates project/PlanetPage.dc.html: the island's own page, the proud view."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
A = ic.ART

coll = [('lemon', 1), ('house', 1), ('pomegranate', 1), ('well', 1), ('rose_arch', 1), ('vegetables', 1), ('flowers', 0), ('jasmine', 0), ('bench', 0)]
thumbs = ''.join(
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 3px; flex-shrink: 0;">'
    f'<div style="width: 46px; height: 46px; border-radius: 14px; background: {"#EEF6EC" if on else "#F5F0E1"}; display: flex; align-items: center; justify-content: center;">'
    f'<img src="{A[n][0]}" alt="" style="width: 38px; height: 38px; object-fit: contain;"></div>'
    f'<span style="width: 6px; height: 6px; border-radius: 999px; background: {"#2F7A3A" if on else "transparent"};"></span></div>'
    for n, on in coll)

dates = [('dates_hababou', 'حبابو', '1 إلى 5', 'done'), ('dates_khalal', 'خلال', '6 إلى 10', 'now'), ('dates_rutab', 'رطب', '11 إلى 15', 'next'), ('dates_tamr', 'تمر', '16 إلى 20', 'later')]
date_cells = ''.join(
    f'<div style="flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 6px 0; border-radius: 14px; '
    f'background: {"#FFF6DA" if st == "now" else "transparent"}; border: {"2px solid #E9B949" if st == "now" else "2px solid transparent"};">'
    f'<img src="{A[n][0]}" alt="" style="width: 30px; height: 40px; object-fit: contain; opacity: {1 if st in ("done", "now") else 0.35};">'
    f'<span style="font-size: 13px; font-weight: 700; color: {"#23352A" if st in ("done", "now") else "#8C948D"};">{ar}</span>'
    f'<span style="font-size: 11px; color: #6B7A6F;">{rng}</span></div>'
    for n, ar, rng, st in dates)

html = f"""<!doctype html>
<html lang="ar">
<head>
<meta charset="utf-8">
<title>The oasis page</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
</style>
</helmet>
<div dir="rtl" style="width: 390px; height: 844px; box-sizing: border-box; background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans Arabic', sans-serif; display: flex; flex-direction: column; overflow: hidden; position: relative;">

<div style="position: relative; width: 390px; height: 436px; flex-shrink: 0; background: #DDF0F1; overflow: hidden;">
<div style="position: absolute; left: 21px; top: 26px;">
<dc-import name="Island" level="24" medals="9" pearls="3" size="348" frame="none" fresh="1" hint-size="348px,387px"></dc-import>
</div>
<div style="position: absolute; top: 50px; left: 8px; right: 8px; display: flex; align-items: center; justify-content: space-between;">
<a href="Profile.dc.html" aria-label="رجوع" style="width: 44px; height: 44px; border-radius: 999px; background: rgba(255,255,255,0.88); display: flex; align-items: center; justify-content: center;"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#23352A" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 6 15 12 9 18"></polyline></svg></a>
<div style="font-size: 18px; font-weight: 700; background: rgba(255,255,255,0.88); padding: 8px 16px; border-radius: 999px;">واحة دوم</div>
<a href="Builder.dc.html" aria-label="رتّب الواحة" style="width: 44px; height: 44px; border-radius: 999px; background: rgba(255,255,255,0.88); display: flex; align-items: center; justify-content: center;"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#23352A" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L19 9l-4-4L4 16z"></path><path d="M13.5 6.5l4 4"></path></svg></a>
</div>
<div style="position: absolute; top: 112px; right: 14px; background: #23352A; color: #F5F0E1; font-size: 13px; line-height: 1.35; padding: 7px 11px; border-radius: 12px; white-space: nowrap;"><span style="font-weight: 700;">بيت دوم</span> · المستوى 15 · 2 سبتمبر</div>
<div style="position: absolute; bottom: 8px; left: 12px; right: 12px; display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px;">
<a href="Play.dc.html" style="font-size: 14px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border-radius: 999px; min-height: 44px; display: flex; align-items: center; justify-content: center; text-decoration: none; box-shadow: 0 2px 8px rgba(30,58,36,0.2);">امشِ فيها</a>
<a href="Builder.dc.html" style="font-size: 14px; font-weight: 700; color: #23352A; background: rgba(255,255,255,0.95); border-radius: 999px; min-height: 44px; display: flex; align-items: center; justify-content: center; text-decoration: none;">رتّب</a>
<a href="Neighbours.dc.html" style="font-size: 14px; font-weight: 700; color: #23352A; background: rgba(255,255,255,0.95); border-radius: 999px; min-height: 44px; display: flex; align-items: center; justify-content: center; text-decoration: none;">جيرانك</a>
</div>
</div>

<div style="padding: 12px 16px 0; display: flex; flex-direction: column; gap: 10px;">

<div style="background: #FFFFFF; border-radius: 20px; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px;">
<div style="display: flex; align-items: center; gap: 12px;">
<div style="width: 54px; height: 30px; border-radius: 9px; background: #F2C14E; border: 2.5px solid #A87D12; color: #4A3200; font-size: 17px; font-weight: 700; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">24</div>
<div style="display: flex; flex-direction: column; gap: 0; min-width: 0;">
<div style="font-size: 16px; font-weight: 700;">المستوى 24 · إطار ذهب</div>
<div style="font-size: 12px; color: #6B7A6F;">يشوفه كل من يزور واحتك في الغرف</div>
</div>
</div>
<div style="height: 7px; background: #EDE6D3; border-radius: 999px; overflow: hidden;"><div style="width: 27%; height: 100%; background: #E9B949; border-radius: 999px;"></div></div>
<div style="display: flex; justify-content: space-between; font-size: 12px; color: #6B7A6F;"><span>الجاي: قوس قزح في المستوى 35</span><span>باقي 11 مستوى</span></div>
</div>

<div style="background: #FFFFFF; border-radius: 20px; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px;">
<div style="display: flex; align-items: center; justify-content: space-between;">
<div style="font-size: 15px; font-weight: 700;">مجموعتك <span style="font-weight: 500; color: #6B7A6F; font-size: 13px;">· 14 شي، 6 في الواحة</span></div>
<a href="Builder.dc.html" style="font-size: 14px; font-weight: 700; color: #2F7A3A; text-decoration: none; min-height: 32px; display: flex; align-items: center;">رتّب</a>
</div>
<div style="display: flex; gap: 6px; overflow: hidden;">{thumbs}</div>
</div>

<div style="background: #FFFFFF; border-radius: 20px; padding: 12px 14px; display: flex; flex-direction: column; gap: 6px;">
<div style="display: flex; align-items: baseline; justify-content: space-between;">
<div style="font-size: 15px; font-weight: 700;">تمر النخلة</div>
<div style="font-size: 12px; color: #6B7A6F;">9 أوسمة · باقي 2 للرطب</div>
</div>
<div style="display: flex; gap: 6px;">{date_cells}</div>
</div>

</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":844}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""
open(os.path.join(HERE, 'project', 'PlanetPage.dc.html'), 'w').write(html)
print(len(html))
