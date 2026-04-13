"""
Genereaza iconitele PNG pentru PWA (ruleaza o singura data la setup).
Necesita: pip install Pillow
"""
from PIL import Image, ImageDraw, ImageFont
import os

def make_icon(size, path):
    img = Image.new("RGB", (size, size), "#0a0a0f")
    draw = ImageDraw.Draw(img)
    # Fundal gradient simulat cu un cerc violet
    margin = size // 8
    draw.ellipse([margin, margin, size - margin, size - margin], fill="#7c3aed")
    # Text "AI"
    font_size = size // 3
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
    except Exception:
        font = ImageFont.load_default()
    text = "AI"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((size - tw) // 2, (size - th) // 2 - margin // 4), text, fill="white", font=font)
    img.save(path)
    print(f"Icon generat: {path}")

if __name__ == "__main__":
    out = os.path.dirname(__file__)
    make_icon(192, os.path.join(out, "icon-192.png"))
    make_icon(512, os.path.join(out, "icon-512.png"))
