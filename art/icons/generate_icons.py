#!/usr/bin/env python3
"""Генерирует пиксельные иконки файлов для PEAK HOUR (32×32 RGBA PNG).

Стиль: плоские заливки из палитры Kaleidos, контур 1 px #2C2A26,
без сглаживания (nearest). Иконки читаются в размерах 16/24/32 px.

Запуск:
    python3 art/icons/generate_icons.py
    python3 art/icons/generate_icons.py --preview /tmp/opencode/icons_preview.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 32

# --- палитра Kaleidos ------------------------------------------------------
OUTLINE = (44, 42, 38, 255)      # #2C2A26
NAVY = (44, 92, 104, 255)        # #2C5C68
TEAL = (47, 127, 143, 255)       # #2F7F8F
TEAL_LIGHT = (131, 199, 212, 255)  # #83C7D4
TEAL_PALE = (230, 245, 247, 255)   # #E6F5F7
WARN = (197, 138, 46, 255)       # #C58A2E
SUCCESS = (63, 143, 94, 255)     # #3F8F5E
ERROR = (194, 91, 74, 255)       # #C25B4A
PAPER = (247, 245, 238, 255)     # #F7F5EE
PAPER_LO = (216, 211, 201, 255)  # #D8D3C9
WHITE = (255, 255, 255, 255)


def canvas() -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def shape(d: ImageDraw.ImageDraw, pts: list[tuple[int, int]], fill, outline=OUTLINE) -> None:
    """Заливка многоугольника + контур 1 px по его периметру."""
    d.polygon(pts, fill=fill)
    if outline is not None:
        d.line(pts + [pts[0]], fill=outline, width=1, joint="curve")


def box(d: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], fill, outline=OUTLINE) -> None:
    """
    Прямоугольник с координатами включительно (как у ImageDraw.rectangle).
    """
    d.rectangle(xy, fill=fill)
    if outline is not None:
        d.rectangle(xy, outline=outline)


def file_text() -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    # страница с отрезанным верхним правым углом
    page = [(7, 4), (19, 4), (25, 10), (25, 27), (7, 27)]
    shape(d, page, PAPER)
    # загнутый уголок
    shape(d, [(19, 4), (25, 10), (19, 10)], PAPER_LO)
    # три строки текста
    d.rectangle((10, 13, 22, 14), fill=NAVY)
    d.rectangle((10, 17, 22, 18), fill=NAVY)
    d.rectangle((10, 21, 18, 22), fill=NAVY)
    return img


def file_sound() -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    # янтарный бейдж со срезанными углами
    badge = [(6, 3), (26, 3), (29, 6), (29, 26), (26, 29), (6, 29), (3, 26), (3, 6)]
    shape(d, badge, WARN)
    # восьмая нота: головка, штиль, флажок
    head = [(9, 21), (11, 19), (15, 19), (17, 21), (17, 24), (15, 26), (11, 26), (9, 24)]
    shape(d, head, OUTLINE)
    d.rectangle((16, 8, 17, 21), fill=OUTLINE)
    shape(d, [(17, 8), (23, 11), (23, 14), (20, 14), (20, 13), (17, 12)], OUTLINE)
    return img


def file_photo() -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    # тёмная рамка
    box(d, (3, 6, 28, 26), NAVY)
    # светлое поле кадра
    box(d, (6, 9, 25, 23), TEAL_PALE)
    # дальняя и ближняя горы
    shape(d, [(6, 23), (13, 12), (19, 23)], TEAL_LIGHT, outline=None)
    shape(d, [(11, 23), (18, 14), (25, 23)], SUCCESS, outline=None)
    # солнце
    d.rectangle((20, 11, 22, 13), fill=WARN)
    return img


def file_video() -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    # тело плёнки
    box(d, (3, 8, 28, 24), NAVY)
    # перфорация сверху и снизу
    for x in (5, 9, 21, 25):
        d.rectangle((x, 10, x + 1, 11), fill=PAPER)
        d.rectangle((x, 21, x + 1, 22), fill=PAPER)
    # play
    shape(d, [(13, 11), (22, 16), (13, 21)], PAPER)
    return img


def folder() -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    body = [(3, 27), (3, 9), (13, 9), (16, 12), (29, 12), (29, 27)]
    shape(d, body, WARN)
    # светлая кромка передней стенки
    d.line([(5, 25), (27, 25)], fill=(226, 175, 91, 255), width=1)
    return img


def packet() -> Image.Image:
    img = canvas()
    d = ImageDraw.Draw(img)
    # конверт
    box(d, (3, 10, 28, 25), PAPER)
    # клапан
    shape(d, [(4, 11), (16, 19), (27, 11)], TEAL_PALE, outline=None)
    d.line([(4, 11), (16, 19)], fill=NAVY, width=1)
    d.line([(16, 19), (27, 11)], fill=NAVY, width=1)
    # нижние сгибы
    d.line([(4, 24), (12, 18)], fill=PAPER_LO, width=1)
    d.line([(27, 24), (19, 18)], fill=PAPER_LO, width=1)
    # входящий пакет: teal-бейдж со стрелкой вниз
    shape(d, [(21, 19), (29, 19), (29, 27), (21, 27)], TEAL)
    d.rectangle((24, 21, 25, 23), fill=WHITE)
    d.polygon([(22, 23), (27, 23), (24, 26)], fill=WHITE)
    return img


ICONS = {
    "file_text": file_text,
    "file_sound": file_sound,
    "file_photo": file_photo,
    "file_video": file_video,
    "folder": folder,
    "packet": packet,
}

# Проверка: только полностью прозрачные или полностью непрозрачные пиксели.
# Это гарантирует отсутствие сглаживания по краям.
def assert_hard_edges(img: Image.Image, name: str) -> None:
    alpha = img.getchannel("A")
    values = set(alpha.getdata())
    assert values <= {0, 255}, f"{name}: найден полупрозрачный пиксель {values}"


def build_preview(path: Path) -> None:
    """Контактный лист: все иконки в 16/24/32 px + увеличение 32 px ×4."""
    scale = 4
    cell_w = 200
    cell_h = 236
    cols = 3
    sheet = Image.new("RGBA", (cols * cell_w, 2 * cell_h), (233, 230, 221, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/dejavu/DejaVuSans.ttf", 15)
        small = ImageFont.truetype("/usr/share/fonts/dejavu/DejaVuSans.ttf", 11)
    except OSError:  # pragma: no cover - depends on system fonts
        font = ImageFont.load_default()
        small = font

    for index, (name, factory) in enumerate(ICONS.items()):
        col = index % cols
        row = index // cols
        x0 = col * cell_w
        y0 = row * cell_h
        d.rectangle((x0 + 4, y0 + 4, x0 + cell_w - 6, y0 + cell_h - 6),
                    fill=(247, 245, 238, 255), outline=(154, 149, 137, 255))
        d.text((x0 + 12, y0 + 10), name, fill=(31, 30, 27, 255), font=font)
        icon = factory()

        # три реальных размера в ряд, каждый на белой «карточке»
        cx = x0 + 12
        for px in (16, 24, 32):
            d.rectangle((cx - 2, y0 + 44, cx + px + 1, y0 + 47 + px),
                        fill=(255, 255, 255, 255), outline=(216, 211, 201, 255))
            sheet.alpha_composite(icon.resize((px, px), Image.Resampling.NEAREST),
                                  (cx, y0 + 46))
            d.text((cx, y0 + 52 + px), f"{px}", fill=(90, 86, 78, 255), font=small)
            cx += 42

        # увеличение 32 px ×4 — чтобы видеть пиксели и контур
        big = icon.resize((SIZE * scale, SIZE * scale), Image.Resampling.NEAREST)
        sheet.alpha_composite(big, (x0 + 34, y0 + 92))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print(f"preview saved: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, default=None,
                        help="куда сохранить контактный лист (PNG)")
    args = parser.parse_args()

    out_dir = Path(__file__).resolve().parent
    for name, factory in ICONS.items():
        img = factory()
        assert_hard_edges(img, name)
        target = out_dir / f"{name}.png"
        img.save(target)
        print(f"saved {target.relative_to(out_dir.parent.parent)} {img.size}")

    if args.preview is not None:
        build_preview(args.preview)


if __name__ == "__main__":
    main()
