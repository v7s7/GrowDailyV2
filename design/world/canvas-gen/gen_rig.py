"""Generates project/Rig.dc.html: Doum assembled from Sheet 11's parts, moved in code.

The smoothest route for the app: leaves sway on their stems, eyes blink,
arms swing from the shoulder, feet step, the body breathes, all from eight
small pictures and a face drawn in code. Shown beside the frame-based Doum
(Sheets 8 and 9) so the two can be compared.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_together import HEAD, TAIL, write
ID = ic.FRAME_IDS
B = lambda n: '/_blob/' + ID[n]

# parts in the body's own pixels (the body is 324 x 314 at the sheet's scale)
# name: left, top, width, height, transform-origin
P = {
    'arm_l': (-44, 132, 102, 98, '80% 22%'),
    'arm_r': (270, 132, 90, 98, '20% 22%'),
    'foot_l': (60, 280, 96, 60, '50% 30%'),
    'foot_r': (166, 281, 99, 58, '50% 30%'),
    'body': (0, 0, 324, 314, '50% 100%'),
    'belly': (64, 180, 196, 98, '50% 50%'),
    'leaf_l': (-29, -146, 199, 176, '91% 97%'),
    'leaf_r': (149, -149, 208, 179, '11% 97%'),
}
ORDER = ['arm_l', 'arm_r', 'foot_l', 'foot_r', 'body', 'belly', 'leaf_l', 'leaf_r']
parts = ''.join(
    f'<img src="{B(n)}" alt="" class="rg-{n.replace("_", "-")}" style="position: absolute; left: {P[n][0]}px; top: {P[n][1]}px; width: {P[n][2]}px; height: {P[n][3]}px; transform-origin: {P[n][4]};">'
    for n in ORDER)
face = ('<svg viewBox="0 0 324 314" width="324" height="314" style="position: absolute; left: 0; top: 0; overflow: visible;" aria-hidden="true">'
        '<ellipse cx="84" cy="142" rx="23" ry="13" fill="#F4A0A8" opacity="0.9"></ellipse>'
        '<ellipse cx="240" cy="142" rx="23" ry="13" fill="#F4A0A8" opacity="0.9"></ellipse>'
        '<g class="rg-eyes" style="transform-origin: 162px 106px;">'
        '<ellipse cx="116" cy="106" rx="17" ry="22" fill="#1E2B1A"></ellipse><circle cx="111" cy="97" r="6.5" fill="#FFFFFF"></circle>'
        '<ellipse cx="208" cy="106" rx="17" ry="22" fill="#1E2B1A"></ellipse><circle cx="203" cy="97" r="6.5" fill="#FFFFFF"></circle></g>'
        '<path class="rg-smile" d="M138 138 Q162 166 186 138" fill="none" stroke="#1E2B1A" stroke-width="6" stroke-linecap="round"></path>'
        '<path class="rg-open" d="M136 134 Q162 182 188 134 Z" fill="#C8394A" stroke="#1E2B1A" stroke-width="5" stroke-linejoin="round"></path>'
        '</svg>')

STYLE = """
.rg{position:absolute;left:0;top:0;width:324px;height:314px;transform-origin:50% 100%}
.rg-open{opacity:0}
@keyframes rg-breathe{0%,100%{transform:none}50%{transform:scale(1.015,1.025)}}
@keyframes rg-leafl{0%,100%{transform:rotate(-3deg)}50%{transform:rotate(4deg)}}
@keyframes rg-leafr{0%,100%{transform:rotate(3deg)}50%{transform:rotate(-4deg)}}
@keyframes rg-blink{0%,92%,100%{transform:scaleY(1)}95%{transform:scaleY(.08)}}
@keyframes rg-bob{0%,50%,100%{transform:translateY(0)}25%,75%{transform:translateY(-10px)}}
@keyframes rg-stepl{0%,100%{transform:translateY(0)}25%{transform:translateY(-16px) rotate(-8deg)}50%{transform:translateY(0)}}
@keyframes rg-stepr{0%,50%,100%{transform:translateY(0)}75%{transform:translateY(-16px) rotate(8deg)}}
@keyframes rg-swingl{0%,100%{transform:rotate(14deg)}50%{transform:rotate(-14deg)}}
@keyframes rg-swingr{0%,100%{transform:rotate(14deg)}50%{transform:rotate(-14deg)}}
@keyframes rg-leafwalkl{0%,100%{transform:rotate(-7deg)}50%{transform:rotate(2deg)}}
@keyframes rg-leafwalkr{0%,100%{transform:rotate(7deg)}50%{transform:rotate(-2deg)}}
@keyframes rg-jump{0%,100%{transform:translateY(0) scale(1,1)}12%{transform:translateY(0) scale(1.08,.9)}40%{transform:translateY(-70px) scale(.95,1.07)}62%{transform:translateY(0) scale(1.06,.93)}75%{transform:translateY(0) scale(1,1)}}
@keyframes rg-flapl{0%,100%{transform:rotate(0)}40%{transform:rotate(-18deg)}}
@keyframes rg-flapr{0%,100%{transform:rotate(0)}40%{transform:rotate(18deg)}}
@keyframes rg-wave{0%,100%{transform:rotate(-70deg)}50%{transform:rotate(-100deg)}}
.m-idle .rg{animation:rg-breathe 3.4s ease-in-out infinite}
.m-idle .rg-leaf-l{animation:rg-leafl 2.9s ease-in-out infinite}
.m-idle .rg-leaf-r{animation:rg-leafr 3.3s ease-in-out infinite}
.rg-eyes{animation:rg-blink 4.8s linear infinite}
.m-walk .rg{animation:rg-bob .44s ease-in-out infinite}
.m-walk .rg-foot-l{animation:rg-stepl .44s ease-in-out infinite}
.m-walk .rg-foot-r{animation:rg-stepr .44s ease-in-out infinite}
.m-walk .rg-arm-l{animation:rg-swingl .44s ease-in-out infinite}
.m-walk .rg-arm-r{animation:rg-swingr .44s ease-in-out infinite reverse}
.m-walk .rg-leaf-l{animation:rg-leafwalkl .44s ease-in-out infinite}
.m-walk .rg-leaf-r{animation:rg-leafwalkr .44s ease-in-out infinite}
.m-happy .rg{animation:rg-jump 1.1s ease-in-out infinite}
.m-happy .rg-leaf-l{animation:rg-flapl 1.1s ease-in-out infinite}
.m-happy .rg-leaf-r{animation:rg-flapr 1.1s ease-in-out infinite}
.m-happy .rg-open,.m-wave .rg-open{opacity:1}.m-happy .rg-smile,.m-wave .rg-smile{opacity:0}
.m-wave .rg{animation:rg-breathe 3.4s ease-in-out infinite}
.m-wave .rg-arm-r{animation:rg-wave .7s ease-in-out infinite}
.m-wave .rg-leaf-l{animation:rg-leafl 1.4s ease-in-out infinite}
.m-wave .rg-leaf-r{animation:rg-leafr 1.6s ease-in-out infinite}
@media (prefers-reduced-motion: reduce){.rg,.rg-leaf-l,.rg-leaf-r,.rg-eyes,.rg-foot-l,.rg-foot-r,.rg-arm-l,.rg-arm-r{animation:none !important}}
""" + ic.STYLE

# the frame-based Doum for comparison
FM = ic.FRAME_META


def frame_imgs(names, classes, scale, ox, oy):
    out = ''
    for n, c in zip(names, classes):
        m = FM[n]
        out += (f'<img src="{B(n)}" alt="" class="{c}" style="position: absolute; left: {ox - m["ax"] * scale:.0f}px; top: {oy - m["ay"] * scale:.0f}px; '
                f'width: {m["w"] * scale:.0f}px; height: {m["h"] * scale:.0f}px;">')
    return out


SC = 300 / FM['idle_calm']['dh']
idle_frames = frame_imgs(['idle_calm', 'idle_blink', 'idle_look_l', 'idle_look_r'], ['', 'isl-blink', 'isl-lookl', 'isl-lookr'], SC, 160, 330)
walk_frames = frame_imgs([f'walk_front_{k}' for k in range(1, 5)], [f'isl-fr isl-fr{i}' for i in range(4)], 300 / FM['walk_front_1']['dh'], 160, 330)

JS = r"""
class Component extends DCLogic {
  renderVals() {
    const st = Object.assign({ mode: 'idle' }, this.state || {});
    const b = {};
    ['idle', 'walk', 'happy', 'wave'].forEach((m) => {
      b[m] = () => this.setState({ mode: m });
      b[m + 'Bg'] = st.mode === m ? '#2F7A3A' : '#FFFFFF';
      b[m + 'Fg'] = st.mode === m ? '#FFFFFF' : '#23352A';
    });
    return { b, mcls: 'm-' + st.mode, framesWalk: st.mode === 'walk', framesIdle: st.mode !== 'walk' };
  }
}
"""
btn = lambda m, ar: (f'<button type="button" onClick="{{{{b.{m}}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: {{{{b.{m}Fg}}}}; '
                     f'background: {{{{b.{m}Bg}}}}; border: 0; border-radius: 999px; min-height: 44px; padding: 0 18px; cursor: pointer; box-shadow: 0 0 0 1px #E1D9C4;">{ar}</button>')
html = HEAD.format(title='Doum from parts', style=STYLE).replace("<html lang=\"ar\">", "<html lang=\"en\">") + f"""<div style="width: 860px; height: 620px; box-sizing: border-box; background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans', 'IBM Plex Sans Arabic', sans-serif; padding: 28px 32px; display: flex; flex-direction: column; gap: 16px;">
<div style="display: flex; justify-content: space-between; align-items: flex-end; gap: 16px;">
<div style="display: flex; flex-direction: column; gap: 4px;">
<div style="font-size: 26px; font-weight: 700;">Doum from parts, moved in code</div>
<div style="font-size: 15px; color: #45574B;">Left: eight pieces from Sheet 11 and a face drawn in code. Right: the drawn frames from Sheets 8 and 9.</div>
</div>
<div dir="rtl" style="display: flex; gap: 8px;">{btn('idle', 'واقف')}{btn('walk', 'يمشي')}{btn('happy', 'فرحان')}{btn('wave', 'يسلّم')}</div>
</div>
<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; flex: 1;">
<div style="background: #DDF0F1; border-radius: 24px; position: relative; overflow: hidden;">
<div style="position: absolute; left: 50%; bottom: 40px; width: 0; height: 0;">
<div style="position: absolute; left: -62px; top: -12px; width: 124px; height: 23px; border-radius: 50%; background: radial-gradient(closest-side, rgba(30,43,26,0.3), rgba(30,43,26,0));"></div>
<div class="{{{{mcls}}}}" style="position: absolute; left: -63px; top: -133px; width: 324px; height: 314px; scale: 0.39; transform-origin: 0 0;">
<div class="rg">{parts}{face}</div>
</div>
</div>
<div style="position: absolute; left: 16px; top: 14px; font-size: 14px; font-weight: 700; background: rgba(255,255,255,0.85); border-radius: 999px; padding: 4px 12px;">Parts · smooth at any speed</div>
</div>
<div style="background: #DDF0F1; border-radius: 24px; position: relative; overflow: hidden;">
<div style="position: absolute; left: 50%; top: 170px; width: 0; height: 0; scale: 0.62; transform-origin: 0 0;">
<div style="position: absolute; left: -160px; top: 0;">
<sc-if value="{{{{framesIdle}}}}" hint-placeholder-val="{{{{true}}}}"><div style="position: absolute; left: 0; top: 0;" class="isl-breathe">{idle_frames}</div></sc-if>
<sc-if value="{{{{framesWalk}}}}" hint-placeholder-val="{{{{false}}}}"><div style="position: absolute; left: 0; top: 0;">{walk_frames}</div></sc-if>
</div>
</div>
<div style="position: absolute; left: 16px; top: 14px; font-size: 14px; font-weight: 700; background: rgba(255,255,255,0.85); border-radius: 999px; padding: 4px 12px;">Frames · richer drawing</div>
</div>
</div>
<div style="font-size: 14px; line-height: 1.5; color: #45574B;">Recommended for the app: the drawn frames for walking and actions (they look best), and the parts for everything that loops all day (breathing, leaves, blinking), so the idle Doum never repeats a stiff picture.</div>
</div>
""" + TAIL.format(js=JS).replace('"width":390,"height":844', '"width":860,"height":620')
write('Rig.dc.html', html)
