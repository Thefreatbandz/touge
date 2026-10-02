"""Playwright test: load TOUGE, race, hold gas, verify the car moves."""
import asyncio, os, re
from urllib.parse import urlparse
from playwright.async_api import async_playwright

def _proxy():
    raw = os.environ.get("https_proxy") or os.environ.get("http_proxy")
    if not raw:
        return None
    u = urlparse(raw)
    return {"server": f"{u.scheme}://{u.hostname}:{u.port}",
            "username": u.username, "password": u.password}

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            proxy=_proxy(),
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        )
        page = await browser.new_page(viewport={"width": 1280, "height": 720})
        errors = []
        page.on("console", lambda m: errors.append(f"{m.type}: {m.text[:200]}") if m.type in ("error", "warning") else None)
        page.on("pageerror", lambda e: errors.append(f"pageerror: {str(e)[:200]}"))
        await page.goto("https://thefreatbandz.github.io/touge/", wait_until="networkidle")
        # wait for the Godot canvas + title (poll for TAP TO RACE via screenshot is hard; just wait)
        await page.wait_for_timeout(15000)
        await page.screenshot(path="/tmp/pw_title.png")
        # click TAP TO RACE (center of screen, around y=480 in 1280x720)
        await page.mouse.click(640, 480)
        await page.wait_for_timeout(3500)  # countdown 3-2-1-GO
        await page.screenshot(path="/tmp/pw_go.png")
        # hold ArrowUp (gas) for 6 seconds
        await page.keyboard.down("ArrowUp")
        await page.wait_for_timeout(6000)
        await page.screenshot(path="/tmp/pw_drive.png")
        await page.keyboard.up("ArrowUp")
        # steer a bit while gassing
        await page.keyboard.down("ArrowUp")
        await page.keyboard.down("ArrowLeft")
        await page.wait_for_timeout(2500)
        await page.keyboard.up("ArrowLeft")
        await page.keyboard.up("ArrowUp")
        await page.screenshot(path="/tmp/pw_turn.png")
        print("CONSOLE ISSUES:", len(errors))
        for e in errors[:15]:
            print(" ", e)
        await browser.close()

asyncio.run(main())
