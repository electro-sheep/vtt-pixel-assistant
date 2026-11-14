"""
Generates crisp, pixel-accurate PNG preview images for the GitHub README
showcasing:
1. docs/images/vtt_assistant_showcase.png (Full 3-Tier Progression + Flat vs Expanded Floor UI)
2. docs/images/tier1_sky_pterodactyl.png
3. docs/images/tier2_hooded_cultist.png
4. docs/images/tier3_apex_green_trex.png
"""

from __future__ import annotations
import json
import math
import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "images")
os.makedirs(OUT_DIR, exist_ok=True)


def get_font(size: int, bold: bool = False):
    candidates = [
        r"C:\Windows\Fonts\consolab.ttf" if bold else r"C:\Windows\Fonts\consola.ttf",
        r"C:\Windows\Fonts\segoeui.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()



def make_grid(w: int, h: int):
    return [[None for _ in range(w)] for _ in range(h)]


def set_px(grid, x: int, y: int, col):
    h = len(grid)
    w = len(grid[0])
    if 0 <= x < w and 0 <= y < h:
        grid[y][x] = col


def fill_rect(grid, x: int, y: int, rw: int, rh: int, col):
    for py in range(y, y + rh):
        for px in range(x, x + rw):
            set_px(grid, px, py, col)


def draw_line(grid, x0: int, y0: int, x1: int, y1: int, col):
    dx = abs(x1 - x0)
    sx = 1 if x0 < x1 else -1
    dy = -abs(y1 - y0)
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    cx, cy = x0, y0
    while True:
        set_px(grid, cx, cy, col)
        if cx == x1 and cy == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            cx += sx
        if e2 <= dx:
            err += dx
            cy += sy


def draw_oval_filled(grid, cx: int, cy: int, rx: int, ry: int, col):
    for py in range(cy - ry, cy + ry + 1):
        for px in range(cx - rx, cx + rx + 1):
            dx = (px - cx) / (rx + 0.25)
            dy = (py - cy) / (ry + 0.25)
            if dx * dx + dy * dy <= 1.0:
                set_px(grid, px, py, col)


def apply_outline(grid, outline_col):
    h = len(grid)
    w = len(grid[0])
    copy = [row[:] for row in grid]
    for y in range(h):
        for x in range(w):
            if copy[y][x] is not None:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and copy[ny][nx] is not None:
                    grid[y][x] = outline_col
                    break


def build_ptero_sprite():
    grid = make_grid(56, 40)
    outline = (8, 20, 30, 255)
    wing_shadow = (0, 96, 100, 255)
    wing_teal = (0, 172, 193, 255)
    wing_sky = (38, 198, 218, 255)
    wing_membrane = (128, 222, 234, 255)
    body_azure = (2, 136, 209, 255)
    belly_cream = (224, 247, 250, 255)
    crest_base = (230, 81, 0, 255)
    crest_amber = (255, 143, 0, 255)
    crest_gold = (255, 213, 79, 255)
    beak_gold = (255, 179, 0, 255)
    beak_tip = (255, 111, 0, 255)
    white = (255, 255, 255, 255)
    pupil = (16, 32, 39, 255)

    cx, cy = 25, 20
    far_x, far_y = cx - 12, cy - 13
    draw_line(grid, cx - 2, cy - 2, far_x, far_y, wing_shadow)
    for wx in range(far_x, cx - 1):
        t = (wx - far_x) / max(1, abs(cx - 2 - far_x))
        top_y = round(far_y + (cy - 2 - far_y) * t)
        bot_y = round(top_y + 4 + t * 4)
        for wy in range(top_y, bot_y + 1):
            set_px(grid, wx, wy, wing_teal if wy == top_y else wing_shadow)

    draw_line(grid, cx - 7, cy + 2, cx - 17, cy + 4, wing_shadow)
    draw_oval_filled(grid, cx - 18, cy + 4, 3, 2, crest_amber)
    set_px(grid, cx - 18, cy + 4, crest_gold)

    draw_oval_filled(grid, cx, cy, 7, 5, body_azure)
    draw_oval_filled(grid, cx + 1, cy - 1, 6, 4, wing_sky)
    draw_oval_filled(grid, cx + 2, cy + 2, 5, 3, belly_cream)

    near_x, near_y = cx - 19, cy - 15
    for wx in range(near_x, cx + 2):
        t = (wx - near_x) / max(1, abs(cx + 1 - near_x))
        spar_y = round(near_y + (cy - 1 - near_y) * t)
        scallop = 1 if (wx % 4 == 0) else 0
        bot = round(spar_y + 3 + t * 6) - scallop
        for wy in range(spar_y, bot + 1):
            c = wing_membrane
            if wy <= spar_y + 1:
                c = wing_sky
            if wy == spar_y:
                c = crest_gold
            if wy >= bot - 1:
                c = wing_teal
            set_px(grid, wx, wy, c)

    fill_rect(grid, cx + 2, cy + 4, 2, 6, wing_shadow)
    fill_rect(grid, cx + 2, cy + 9, 4, 2, crest_amber)
    fill_rect(grid, cx - 2, cy + 4, 2, 7, body_azure)
    fill_rect(grid, cx - 2, cy + 10, 4, 2, beak_gold)

    head_x, head_y = cx + 6, cy - 7
    for cr in range(11):
        cr_x = head_x - cr
        cr_y = head_y - 1 - (cr // 2)
        cr_h = max(1, min(4, 4 - (cr // 3)))
        for dy in range(cr_h):
            c = crest_gold if dy == 0 else (crest_amber if dy == 1 else crest_base)
            set_px(grid, cr_x, cr_y + dy, c)

    fill_rect(grid, cx + 4, cy - 4, 4, 5, wing_sky)
    fill_rect(grid, head_x - 1, head_y, 7, 5, wing_sky)
    fill_rect(grid, head_x, head_y - 1, 5, 2, crest_amber)

    for bx in range(13):
        h = max(1, min(3, 3 - (bx // 4)))
        for by in range(h):
            set_px(
                grid,
                head_x + 6 + bx,
                head_y + 1 + by + (bx // 6),
                beak_tip if bx > 8 else (crest_gold if by == 0 else beak_gold),
            )
    for bx in range(10):
        set_px(grid, head_x + 6 + bx, head_y + 6 + (bx // 5), beak_tip if bx > 6 else crest_base)

    fill_rect(grid, head_x + 2, head_y + 1, 3, 2, white)
    set_px(grid, head_x + 3, head_y + 1, pupil)
    apply_outline(grid, outline)
    return grid


def build_cultist_sprite():
    """
    Draws both the Gungeon Ember Void Cultist (left) and Terraria Lunatic Beak Cultist (right)
    in a 56x40 showcase grid so both skins are visible!
    """
    grid = make_grid(56, 40)
    outline = (20, 6, 28, 255)

    # --- 1. LEFT: GUNGEON EMBER VOID CULTIST (Image 1 Reference) ---
    hood_red = (212, 50, 20, 255)
    hood_orange = (229, 100, 26, 255)
    hood_purple = (123, 16, 94, 255)
    gold_bright = (255, 238, 24, 255)
    gold_mid = (230, 184, 18, 255)
    gold_shadow = (168, 123, 18, 255)
    void_navy = (4, 8, 40, 255)
    eye_cyan = (24, 160, 248, 255)
    white = (255, 255, 255, 255)
    emerald = (0, 232, 74, 255)

    cx, hood_y = 14, 7
    hood_bounds = [
        (-4, 4), (-6, 5), (-7, 6), (-8, 7), (-9, 8),
        (-9, 8), (-9, 9), (-9, 9), (-9, 9), (-9, 8),
        (-9, 8), (-8, 7), (-7, 6), (-6, 5),
    ]
    for r, (xmin, xmax) in enumerate(hood_bounds):
        y = hood_y + r
        for dx in range(xmin, xmax + 1):
            c = hood_orange
            if r <= 1:
                c = hood_purple if dx >= 2 else hood_red
            elif dx >= xmax - 2:
                c = hood_purple
            elif r <= 3:
                c = hood_red
            set_px(grid, cx + dx, y, c)

    face_cx, face_cy = cx - 1, hood_y + 8
    draw_oval_filled(grid, face_cx, face_cy, 6, 5, gold_bright)
    for py in range(face_cy + 1, face_cy + 6):
        for px in range(face_cx - 6, face_cx + 7):
            if grid[py][px] == gold_bright:
                grid[py][px] = gold_shadow if py >= face_cy + 3 else gold_mid
    draw_oval_filled(grid, face_cx, face_cy + 1, 5, 4, void_navy)

    # 1x2 Cyan + White eyes
    fill_rect(grid, face_cx - 3, face_cy, 1, 1, eye_cyan)
    fill_rect(grid, face_cx - 3, face_cy + 1, 1, 1, white)
    fill_rect(grid, face_cx + 2, face_cy, 1, 1, eye_cyan)
    fill_rect(grid, face_cx + 2, face_cy + 1, 1, 1, white)

    robe_top = hood_y + 13
    robe_bot = hood_y + 23
    for ry in range(robe_top, robe_bot + 1):
        prog = (ry - robe_top) / 10.0
        hw = round(5 + prog * 3.0)
        for rx in range(cx - hw, cx + hw + 1):
            c = hood_orange
            if rx >= cx + hw - 2:
                c = hood_purple
            elif abs(rx - face_cx) <= 1:
                c = hood_red
            if ry >= robe_bot - 1:
                c = gold_shadow if (rx == face_cx or rx >= cx + hw - 2) else gold_bright
            set_px(grid, rx, ry, c)

    # Emerald Brooch Clasp
    fill_rect(grid, face_cx - 1, robe_top, 3, 3, gold_bright)
    set_px(grid, face_cx, robe_top + 1, emerald)
    # Sleeves & hands
    fill_rect(grid, cx - 7, robe_top + 3, 2, 1, gold_bright)
    fill_rect(grid, cx - 7, robe_top + 4, 2, 2, void_navy)
    fill_rect(grid, cx + 3, robe_top + 3, 3, 1, gold_bright)
    fill_rect(grid, cx + 3, robe_top + 4, 3, 2, void_navy)

    # --- 2. RIGHT: TERRARIA LUNATIC BEAK CULTIST (Image 2 Reference) ---
    blue_deep = (14, 29, 102, 255)
    blue_royal = (28, 59, 158, 255)
    blue_cobalt = (46, 92, 230, 255)
    mask_white = (248, 248, 255, 255)
    mask_lav = (214, 203, 226, 255)

    lcx, ltop = 41, 7
    for r in range(11):
        y = ltop + r
        lx = lcx - 5
        rx = lcx + 6 + (r // 3)
        for x in range(lx, rx + 1):
            c = blue_royal
            if r <= 1 and x <= lcx + 1:
                c = gold_bright
            elif x <= lx + 1 and r <= 8:
                c = gold_bright if r < 5 else gold_mid
            elif x >= rx - 2:
                c = blue_deep
            set_px(grid, x, y, c)
    # Swept-back hood tail to right
    for tx in range(5):
        fill_rect(grid, lcx + 6 + tx, ltop + 3 - (tx // 2), 2, 3, blue_royal)

    # White Plague Beak Mask jutting left
    for bx in range(7):
        by_top = ltop + 3 + ((bx * bx) // 12)
        by_bot = ltop + 8 - (bx // 3)
        for by in range(by_top, max(by_top + 1, by_bot + 1)):
            set_px(grid, lcx - 5 - bx, by, mask_lav if by == by_bot else mask_white)
    fill_rect(grid, lcx - 6, ltop + 4, 2, 2, void_navy)

    lrobe_top = ltop + 11
    lrobe_bot = ltop + 23
    for ry in range(lrobe_top, lrobe_bot + 1):
        prog = (ry - lrobe_top) / 12.0
        hw = round(5 + prog * 4.5)
        for rx in range(lcx - hw, lcx + hw + 1):
            c = blue_cobalt if (rx < lcx - 1) else (blue_deep if rx > lcx + 2 else blue_royal)
            if ry == lrobe_top + 1 + abs(rx - lcx) // 2 and abs(rx - lcx) <= 5:
                c = gold_bright
            if ry == lrobe_top + 6 + abs(rx - lcx) // 2 and abs(rx - lcx) <= 5:
                c = gold_mid
            set_px(grid, rx, ry, c)

    apply_outline(grid, outline)
    return grid


def build_trex_sprite():
    grid = make_grid(56, 40)
    outline = (10, 25, 12, 255)
    dark_green = (27, 94, 32, 255)
    mid_green = (46, 125, 50, 255)
    bright_green = (67, 160, 71, 255)
    lime_scale = (129, 199, 132, 255)
    belly_cream = (220, 237, 200, 255)
    belly_shadow = (174, 213, 129, 255)
    eye_gold = (255, 213, 79, 255)
    pupil = (17, 17, 17, 255)
    white = (255, 255, 255, 255)
    tongue_red = (229, 57, 53, 255)

    for tx in range(2, 21):
        progress = (20 - tx) / 18.0
        sway = round(math.sin(progress * 2.6) * 1.4)
        thick = round(1 + (1.0 - progress) * 4.6)
        cy = 21 + sway - round(progress * 2)
        for dy in range(-thick, thick + 1):
            col = mid_green
            if dy == -thick:
                col = bright_green
            if dy >= thick - 1:
                col = belly_shadow
            if dy == -thick and tx % 3 == 0:
                col = lime_scale
            set_px(grid, tx, cy + dy, col)

    draw_oval_filled(grid, 26, 21, 9, 7, mid_green)
    draw_oval_filled(grid, 25, 19, 8, 4, bright_green)
    draw_oval_filled(grid, 28, 24, 6, 3, belly_cream)
    for sx in range(18, 32, 2):
        set_px(grid, sx, 14, lime_scale)
        set_px(grid, sx, 15, lime_scale)
        set_px(grid, sx + 1, 16, bright_green)

    fill_rect(grid, 28, 27, 4, 5, dark_green)
    fill_rect(grid, 29, 32, 3, 3, dark_green)
    fill_rect(grid, 29, 34, 5, 2, dark_green)
    set_px(grid, 34, 35, white)

    draw_oval_filled(grid, 23, 28, 3, 3, mid_green)
    fill_rect(grid, 22, 30, 4, 4, mid_green)
    fill_rect(grid, 23, 33, 3, 2, bright_green)
    fill_rect(grid, 22, 34, 6, 2, mid_green)
    set_px(grid, 28, 35, white)
    set_px(grid, 26, 35, white)

    fill_rect(grid, 32, 20, 4, 2, bright_green)
    fill_rect(grid, 35, 21, 3, 2, mid_green)
    set_px(grid, 38, 21, white)
    set_px(grid, 38, 22, white)

    head_y = 7
    fill_rect(grid, 28, head_y + 5, 7, 6, mid_green)
    fill_rect(grid, 29, head_y + 4, 6, 3, bright_green)
    fill_rect(grid, 30, head_y + 1, 16, 6, mid_green)
    fill_rect(grid, 31, head_y, 14, 3, bright_green)
    fill_rect(grid, 45, head_y + 2, 3, 5, mid_green)
    fill_rect(grid, 32, head_y - 1, 7, 2, lime_scale)
    fill_rect(grid, 34, head_y + 1, 4, 3, eye_gold)
    fill_rect(grid, 36, head_y + 1, 2, 2, pupil)
    set_px(grid, 34, head_y + 1, white)

    for tx in range(35, 47, 2):
        set_px(grid, tx, head_y + 7, white)
    fill_rect(grid, 32, head_y + 7, 10, 2, tongue_red)
    fill_rect(grid, 30, head_y + 10, 16, 3, mid_green)
    for tx in range(36, 46, 2):
        set_px(grid, tx, head_y + 9, white)

    apply_outline(grid, outline)
    return grid


def build_floor_grid(is_cultist: bool):
    w, h = 110, 10
    grid = make_grid(w, h)
    if is_cultist:
        stone_dark = (26, 18, 36, 255)
        stone_mid = (45, 34, 59, 255)
        stone_hi = (74, 59, 92, 255)
        mortar = (14, 8, 20, 255)
        rune_glow = (234, 128, 252, 255)
        rune_cyan = (0, 229, 255, 255)
        moss = (46, 125, 50, 255)
        wax = (255, 248, 225, 255)
        flame_gold = (255, 213, 79, 255)
        flame_orange = (255, 109, 0, 255)

        fill_rect(grid, 0, 6, w, 4, stone_mid)
        fill_rect(grid, 0, 6, w, 1, stone_hi)
        fill_rect(grid, 0, 9, w, 1, stone_dark)
        for x in range(w):
            if x % 11 == 0:
                fill_rect(grid, x, 6, 1, 4, mortar)
            if x % 19 == 5:
                set_px(grid, x, 5, moss)
                set_px(grid, x + 1, 6, moss)
            if x % 16 == 8 and 10 < x < w - 10:
                r_col = rune_cyan if (x % 32 == 8) else rune_glow
                set_px(grid, x, 7, r_col)
                set_px(grid, x + 1, 8, r_col)
                set_px(grid, x + 2, 7, r_col)
        for i, cx in enumerate((4, 9, w - 10, w - 5)):
            ch = 4 if i % 2 == 0 else 3
            fill_rect(grid, cx, 6 - ch, 2, ch, wax)
            set_px(grid, cx, 5 - ch, flame_gold)
            set_px(grid, cx + 1, 5 - ch, flame_orange)
    else:
        soil_dark = (39, 25, 17, 255)
        soil_mid = (62, 39, 35, 255)
        turf_base = (27, 94, 32, 255)
        grass_mid = (46, 125, 50, 255)
        grass_bright = (67, 160, 71, 255)
        grass_neon = (105, 240, 174, 255)
        flower_amber = (255, 213, 79, 255)

        fill_rect(grid, 0, 7, w, 3, soil_mid)
        fill_rect(grid, 0, 9, w, 1, soil_dark)
        fill_rect(grid, 0, 5, w, 2, turf_base)
        for x in range(w):
            if x % 4 == 0:
                set_px(grid, x, 7, turf_base)
            h_val = ((x * 37 + 13) % 7) % 4 + 1
            for dy in range(1, h_val + 1):
                c = grass_neon if (dy == h_val and x % 5 == 0) else (grass_bright if dy >= 2 else grass_mid)
                set_px(grid, x, 5 - dy, c)
            if x % 23 == 11:
                set_px(grid, x, 2, flower_amber)
    return grid


def paste_pixel_grid(img: Image.Image, grid, left: int, top: int, scale: int):
    draw = ImageDraw.Draw(img)
    for y, row in enumerate(grid):
        for x, col in enumerate(row):
            if col is None:
                continue
            x0 = left + x * scale
            y0 = top + y * scale
            draw.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=col)


def render_creature_card(
    filename: str,
    title: str,
    tier_badge: str,
    vram_badge: str,
    desc_line: str,
    sprite_grid,
    floor_grid,
    accent_rgb,
    flat_bar_text: str,
):
    img = Image.new("RGBA", (460, 320), (13, 17, 23, 255))
    draw = ImageDraw.Draw(img)
    font_title = get_font(13, bold=True)
    font_sub = get_font(11, bold=False)
    font_bar = get_font(11, bold=True)

    # Card border
    draw.rectangle([4, 4, 455, 315], outline=accent_rgb, width=3)
    draw.rectangle([12, 12, 447, 58], fill=(22, 29, 41, 255), outline=(45, 58, 78, 255))

    draw.text((20, 17), f"{tier_badge}  |  {title}", fill=accent_rgb, font=font_title)
    draw.text((20, 36), f"{vram_badge}  -  {desc_line}", fill=(176, 190, 197, 255), font=font_sub)

    # Draw creature standing ON TOP of the terrain floor
    sprite_scale = 4
    sprite_w = 56 * sprite_scale
    sprite_h = 40 * sprite_scale
    sprite_x = (460 - sprite_w) // 2
    sprite_y = 74
    paste_pixel_grid(img, sprite_grid, sprite_x, sprite_y, sprite_scale)

    # Terrain floor right underneath the creature's feet
    floor_x = 32
    floor_y = sprite_y + sprite_h - 14
    paste_pixel_grid(img, floor_grid, floor_x, floor_y, 3)

    # Flat Floor Bar underneath the grass/cobblestone terrain
    bar_top = floor_y + 30
    draw.rectangle(
        [floor_x, bar_top, floor_x + 396, bar_top + 34],
        fill=(18, 24, 20, 255),
        outline=accent_rgb,
        width=2,
    )
    draw.rectangle([floor_x + 8, bar_top + 7, floor_x + 60, bar_top + 27], outline=(0, 230, 118, 255), width=2)
    draw.text((floor_x + 13, bar_top + 11), "REC", fill=(0, 230, 118, 255), font=font_bar)
    draw.text((floor_x + 70, bar_top + 11), flat_bar_text, fill=(255, 245, 157, 255), font=font_bar)

    out_path = os.path.join(OUT_DIR, filename)
    img.save(out_path)
    return out_path


def render_full_showcase():
    ptero = build_ptero_sprite()
    cultist = build_cultist_sprite()
    trex = build_trex_sprite()
    grass = build_floor_grid(is_cultist=False)
    stone = build_floor_grid(is_cultist=True)

    p1 = render_creature_card(
        "tier1_sky_pterodactyl.png",
        "SKY PTERODACTYL",
        "TIER 1: LIGHTWEIGHT",
        "small.en (~0.5 GB)",
        "Fast live dictation on swaying grass",
        ptero,
        grass,
        (38, 198, 218, 255),
        "Click creature to transcribe [98*] [EXPAND]",
    )
    p2 = render_creature_card(
        "tier2_hooded_cultist.png",
        "HOODED CULTIST",
        "TIER 2: GRAMMARLY SCRIBE",
        "medium.en (~1.5 GB)",
        "Robed scribe + 4-Pillar Grammarly helper",
        cultist,
        stone,
        (206, 147, 216, 255),
        "\"They're writing clearly.\" [100*] [EXPAND]",
    )
    p3 = render_creature_card(
        "tier3_apex_green_trex.png",
        "APEX GREEN T-REX",
        "TIER 3: MAX POWER",
        "large-v3-turbo (~2.0 GB)",
        "Heavyweight GPU accuracy + page sync",
        trex,
        grass,
        (102, 187, 106, 255),
        "\"Live words stream to page!\" [99*] [EXPAND]",
    )

    # Combine into a 1420x520 full GitHub Hero Showcase Banner including the Expanded Grammarly Floor Drawer
    banner = Image.new("RGBA", (1420, 520), (9, 12, 18, 255))
    draw = ImageDraw.Draw(banner)
    font_h1 = get_font(15, bold=True)
    font_body = get_font(13, bold=True)
    draw.rectangle([2, 2, 1417, 517], outline=(0, 229, 255, 255), width=2)
    draw.text(
        (24, 15),
        "VTT PIXEL ASSISTANT v3.3  |  100% LOCAL VOICE DICTATION, 3-TIER AI PROGRESSION & GRAMMARLY / DYSLEXIA ENGINE",
        fill=(0, 229, 255, 255),
        font=font_h1,
    )

    c1 = Image.open(p1)
    c2 = Image.open(p2)
    c3 = Image.open(p3)
    banner.paste(c1, (16, 48))
    banner.paste(c2, (480, 48))
    banner.paste(c3, (944, 48))

    # Bottom Expanded Floor Drawer Preview Strip
    draw.rectangle([16, 382, 1404, 502], fill=(20, 16, 32, 255), outline=(186, 104, 200, 255), width=2)
    draw.text(
        (32, 394),
        "EXPANDED UNDER-CREATURE FLOOR DRAWER (Click the flat grass/cobblestone bar underneath your creature to expand):",
        fill=(255, 213, 79, 255),
        font=font_body,
    )
    draw.text(
        (32, 419),
        ">> LIVE STREAM TO PAGE :  Heard: \"their going in order to test\"  -->  Auto-Polished: \"They're going to test.\" (Atomic Win32 Clipboard Diff)",
        fill=(255, 245, 157, 255),
        font=font_body,
    )
    draw.text(
        (32, 444),
        ">> GRAMMARLY 4-PILLAR ENGINE :  Score: 96/100  |  Correctness: 98  |  Clarity: 92  |  Engagement: 95  |  Tone: Direct & Clear",
        fill=(128, 216, 255, 255),
        font=font_body,
    )
    draw.text(
        (32, 469),
        ">> 1-CLICK HELPER RECOMMENDATIONS :  [ENGAGEMENT] \"really good\" -> \"excellent\" [HELPER FIX]   |   [CLARITY] \"a lot of\" -> \"many\" [HELPER FIX]",
        fill=(105, 240, 174, 255),
        font=font_body,
    )

    showcase_path = os.path.join(OUT_DIR, "vtt_assistant_showcase.png")
    banner.save(showcase_path)
    print("Generated preview images:", showcase_path, p1, p2, p3)


if __name__ == "__main__":
    render_full_showcase()
