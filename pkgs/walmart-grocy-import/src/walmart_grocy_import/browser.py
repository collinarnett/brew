"""Lightpanda browser lifecycle and page rendering."""

import subprocess
import time

from playwright.sync_api import sync_playwright

CDP_HOST = "127.0.0.1"
CDP_PORT = 9222


class LightpandaBrowser:
    """Manages a Lightpanda CDP server and provides authenticated page rendering.

    Use as a context manager to ensure the browser process is cleaned up:

        with LightpandaBrowser(cookies) as browser:
            html = browser.render("https://example.com")
    """

    def __init__(self, pw_cookies: list[dict]):
        self._pw_cookies = pw_cookies
        self._proc: subprocess.Popen | None = None

    def _start(self) -> None:
        self._proc = subprocess.Popen(
            ["lightpanda", "serve", "--host", CDP_HOST, "--port", str(CDP_PORT)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(2)

    def _stop(self) -> None:
        if self._proc:
            self._proc.terminate()
            self._proc.wait()
            self._proc = None

    def render(self, url: str) -> str:
        """Render a URL with cookies injected and return the page HTML."""
        with sync_playwright() as p:
            browser = p.chromium.connect_over_cdp(f"ws://{CDP_HOST}:{CDP_PORT}")
            context = browser.new_context()
            context.add_cookies(self._pw_cookies)
            page = context.new_page()
            page.goto(url, wait_until="networkidle", timeout=30000)
            html = page.content()
            browser.close()
        return html

    def render_unauthenticated(self, url: str) -> str:
        """Render a URL without cookies via lightpanda fetch CLI."""
        result = subprocess.run(
            ["lightpanda", "fetch", "--dump", "html", url],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Lightpanda fetch failed: {result.stderr}")
        return result.stdout

    def __enter__(self) -> "LightpandaBrowser":
        self._start()
        return self

    def __exit__(self, *_: object) -> None:
        self._stop()
