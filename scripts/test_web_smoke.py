"""Touch-screen Web smoke test; serve build/web on PB_WEB_SMOKE_URL first."""

import os
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright


OUTPUT = Path("build/web-smoke")
OUTPUT.mkdir(parents=True, exist_ok=True)
URL = os.environ.get("PB_WEB_SMOKE_URL", "http://127.0.0.1:8765/")


with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        executable_path="C:/Program Files/Google/Chrome/Application/chrome.exe",
        headless=True,
        args=["--enable-webgl", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
    )
    page = browser.new_page(viewport={"width": 844, "height": 390}, has_touch=True)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
    response = page.goto(URL, wait_until="domcontentloaded")
    assert response.status == 200
    page.wait_for_selector("#status", state="detached", timeout=60000)
    page.touchscreen.tap(80, 165)  # Base
    page.touchscreen.tap(620, 305)  # Draw three cards
    page.wait_for_timeout(300)
    offer = OUTPUT / "mobile-offer.png"
    page.screenshot(path=str(offer))
    pixels = Image.open(offer).convert("RGB")
    card_text_pixels = sum(
        max(pixels.getpixel((x, y))) > 145
        for x in range(70, 780, 2)
        for y in range(115, 190, 2)
    )
    assert card_text_pixels > 100, "Three-card offer has no visible card content"
    page.touchscreen.tap(160, 150)  # Pick first card
    page.wait_for_timeout(200)
    page.touchscreen.tap(714, 18)  # Open touch controls
    page.screenshot(path=str(OUTPUT / "mobile-controls.png"))
    page.set_viewport_size({"width": 390, "height": 844})
    page.wait_for_timeout(200)
    assert page.locator("#orientation-help").evaluate("e => getComputedStyle(e).display") == "flex"
    page.screenshot(path=str(OUTPUT / "mobile-portrait.png"))
    assert not errors, errors
    print("Web touch smoke passed: offer, controls, portrait prompt, no browser errors")
    browser.close()
