"""Regenerate VoiceMate's vector sources and launcher icons with Pillow."""

from pathlib import Path
import hashlib
import json
import math

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "apps/client/web"
RES = ROOT / "apps/client/android/app/src/main/res"
SIZE = 2048
HEIGHTS = (.22, .43, .60, .43, .22)
BAR_WIDTH = .075
CENTERS = (.25, .375, .5, .625, .75)
TOP = (54, 142, 135)
BOTTOM = (16, 77, 81)
PAPER = (230, 245, 241, 255)


def bars(size):
    for center, height in zip(CENTERS, HEIGHTS):
        yield ((center - BAR_WIDTH / 2) * size, (1 - height) / 2 * size,
               (center + BAR_WIDTH / 2) * size, (1 + height) / 2 * size)


def capsule_path(bounds):
    x0, y0, x1, y1 = bounds
    radius = (x1 - x0) / 2
    return (f"M{x0:.4f},{y0 + radius:.4f}"
            f"A{radius:.4f},{radius:.4f} 0 0 1 {x1:.4f},{y0 + radius:.4f}"
            f"V{y1 - radius:.4f}"
            f"A{radius:.4f},{radius:.4f} 0 0 1 {x0:.4f},{y1 - radius:.4f}Z")


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content + "\n", encoding="utf-8", newline="\n")


def render():
    # A diagonal base and a narrow top highlight mirror the app's VoiceMark.
    diagonal = [tuple(round(a + (b - a) * i / (2 * SIZE - 2))
                      for a, b in zip(TOP, BOTTOM)) for i in range(2 * SIZE - 1)]
    image = Image.new("RGB", (SIZE, SIZE))
    image.putdata([diagonal[x + y] for y in range(SIZE) for x in range(SIZE)])
    image = image.convert("RGBA")
    highlight = Image.new("RGBA", image.size, (255, 255, 255, 0))
    alpha = Image.linear_gradient("L").resize((SIZE, SIZE)).point(
        lambda value: round(19 * max(0, 1 - value / 80)))
    highlight.putalpha(alpha)
    image = Image.alpha_composite(image, highlight)
    draw = ImageDraw.Draw(image)
    for bounds in bars(SIZE):
        draw.rounded_rectangle(bounds, radius=BAR_WIDTH * SIZE / 2, fill=PAPER)
    return image


def save_png(image, path, size, rounded=False):
    output = image.copy()
    if rounded:
        mask = Image.new("L", image.size)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, SIZE - 1, SIZE - 1), radius=SIZE * .235, fill=255)
        output.putalpha(mask)
    path.parent.mkdir(parents=True, exist_ok=True)
    output.resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)
    with Image.open(path) as saved:
        assert saved.size == (size, size), path
        if not rounded:
            assert saved.getextrema()[3] == (255, 255), path


def main():
    # The Android adaptive mark fits inside the platform's 66/108 safe circle.
    for x0, y0, x1, y1 in bars(108):
        radius = (x1 - x0) / 2
        assert radius + math.hypot((x0 + x1) / 2 - 54,
                                   (y1 - y0) / 2 - radius) <= 33

    image = render()
    save_png(image, WEB / "icons/app-icon-1024.png", 1024)
    for size in (192, 512):
        save_png(image, WEB / f"icons/icon-{size}.png", size, rounded=True)
        save_png(image, WEB / f"icons/icon-maskable-{size}.png", size)
    save_png(image, WEB / "icons/apple-touch-icon.png", 180)
    save_png(image, WEB / "favicon.png", 32, rounded=True)
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        save_png(image, RES / f"mipmap-{density}/ic_launcher.png", size, rounded=True)

    svg_bars = "\n".join(
        f'    <rect x="{x0:.2f}" y="{y0:.2f}" width="{x1-x0:.2f}" '
        f'height="{y1-y0:.2f}" rx="{(x1-x0)/2:.2f}"/>'
        for x0, y0, x1, y1 in bars(1024))
    write(WEB / "icons/app-icon.svg", f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>VoiceMate</title>
  <defs>
    <linearGradient id="base" x2="1" y2="1">
      <stop stop-color="#368e87"/><stop offset="1" stop-color="#104d51"/>
    </linearGradient>
    <linearGradient id="light" x2="0" y2="1">
      <stop stop-color="white" stop-opacity=".075"/><stop offset=".314" stop-color="white" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <path fill="url(#base)" d="M0 0h1024v1024H0z"/>
  <path fill="url(#light)" d="M0 0h1024v1024H0z"/>
  <g fill="#e6f5f1">
{svg_bars}
  </g>
</svg>''')
    paths = "\n".join(
        f'    <path android:fillColor="#e6f5f1" android:pathData="{capsule_path(bounds)}"/>'
        for bounds in bars(108))
    vector = f'''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
{paths}
</vector>'''
    write(RES / "drawable/ic_launcher_foreground.xml", vector)
    write(RES / "drawable/ic_launcher_monochrome.xml", vector.replace("#e6f5f1", "#ffffff"))
    write(RES / "drawable/ic_launcher_background.xml", '''<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:startColor="#368e87" android:endColor="#104d51" android:angle="315"/>
</shape>''')
    write(RES / "values/icon_colors.xml", '''<resources>
    <color name="ic_launcher_background">#176b67</color>
</resources>''')
    adaptive = '''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
{monochrome}</adaptive-icon>'''
    write(RES / "mipmap-anydpi-v26/ic_launcher.xml", adaptive.format(monochrome=""))
    write(RES / "mipmap-anydpi-v33/ic_launcher.xml", adaptive.format(
        monochrome='    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'))
    manifest = {
        "name": "VoiceMate", "short_name": "VoiceMate", "lang": "ko",
        "description": "음량 확인, 발음 훈련, 높낮이 연습",
        "start_url": "./", "scope": "./", "display": "standalone",
        "background_color": "#f2f5f7", "theme_color": "#f2f5f7",
        "icons": [
            {"src": f"icons/icon-{prefix}{size}.png", "sizes": f"{size}x{size}",
             "type": "image/png", "purpose": purpose}
            for prefix, purpose in (("", "any"), ("maskable-", "maskable"))
            for size in (192, 512)
        ],
    }
    write(WEB / "manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    for icon in manifest["icons"]:
        assert (WEB / icon["src"]).is_file()
    outputs = [WEB / "favicon.png", WEB / "manifest.json", *sorted((WEB / "icons").glob("*")),
               *sorted(RES.glob("mipmap*/ic_launcher*")), *sorted(RES.glob("drawable/ic_launcher*.xml")),
               RES / "values/icon_colors.xml"]
    print(json.dumps({str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in outputs}, indent=2))


if __name__ == "__main__":
    main()
