"""One-off generator for the StudyVault launcher icon (no design asset existed
before — the app was still shipping Flutter's default template icon).
Run: python tool/gen_app_icon.py
Outputs assets/icon/app_icon.png (flat, legacy icon) and
assets/icon/app_icon_foreground.png (transparent, adaptive-icon foreground),
consumed by flutter_launcher_icons (see pubspec.yaml).
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
ACCENT = (108, 99, 255, 255)  # AppColors.accent #6C63FF
WHITE = (255, 255, 255, 255)
FONT_PATH = r"C:\Windows\Fonts\arialbd.ttf"


def rounded_square(bg_color):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=SIZE // 5, fill=bg_color)
    return img, draw


def draw_monogram(draw, color, font_size):
    font = ImageFont.truetype(FONT_PATH, font_size)
    text = "SV"
    bbox = draw.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pos = ((SIZE - w) / 2 - bbox[0], (SIZE - h) / 2 - bbox[1])
    draw.text(pos, text, font=font, fill=color)


# Legacy flat icon: purple rounded square + white monogram baked in.
flat, flat_draw = rounded_square(ACCENT)
draw_monogram(flat_draw, WHITE, 420)
flat.convert("RGB").save("assets/icon/app_icon.png")

# Adaptive-icon foreground: transparent bg, monogram sized within the ~66%
# safe zone so it isn't clipped by the OS's adaptive icon mask.
fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
fg_draw = ImageDraw.Draw(fg)
draw_monogram(fg_draw, WHITE, 300)
fg.save("assets/icon/app_icon_foreground.png")

print("Generated assets/icon/app_icon.png and app_icon_foreground.png")
