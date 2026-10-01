"""Local Web export smoke test; requires playwright and a server on port 8765."""

from pathlib import Path

from playwright.sync_api import sync_playwright


OUTPUT = Path("build/web-smoke")
OUTPUT.mkdir(parents=True, exist_ok=True)

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        executable_path="C:/Program Files/Google/Chrome/Application/chrome.exe",
        headless=True,
        args=["--enable-webgl", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
    )
    page = browser.new_page(viewport={"width": 844, "height": 390}, has_touch=True)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    response = page.goto("http://127.0.0.1:8765/", wait_until="domcontentloaded")
    page.wait_for_timeout(20000)
    print("HTTP:", response.status)
    print("Title:", page.title())
    print("Canvas:", page.locator("canvas").evaluate("e => [e.width, e.height]"))
    print("Loading overlay remaining:", page.locator("#status").count())
    print("Page errors:", errors)
    page.screenshot(path=str(OUTPUT / "mobile-landscape.png"))
    page.touchscreen.tap(705, 30)
    page.wait_for_timeout(500)
    page.screenshot(path=str(OUTPUT / "mobile-menu.png"))
    page.touchscreen.tap(705, 30)
    page.touchscreen.tap(170, 160)
    page.wait_for_timeout(500)
    page.screenshot(path=str(OUTPUT / "mobile-base-selected.png"))
    browser.close()
