"""Lightpanda browser lifecycle and page rendering."""

import subprocess
import time
from typing import Self

from playwright.sync_api import sync_playwright

CDP_HOST = "127.0.0.1"
CDP_PORT = 9222
CDP_STARTUP_DELAY = 2
RENDER_TIMEOUT = 30000
FETCH_TIMEOUT = 30


class LightpandaBrowser:
    """Manages a Lightpanda CDP server and provides authenticated page rendering.

    Use as a context manager to ensure the browser process is cleaned up::

        with LightpandaBrowser(cookies) as browser:
            html = browser.render("https://example.com")
    """

    def __init__(self, pw_cookies: list[dict[str, object]]) -> None:
        """Initialize with Playwright-format cookies."""
        self._pw_cookies = pw_cookies
        self._proc: subprocess.Popen[bytes] | None = None

    def _start(self) -> None:
        cmd = [
            "lightpanda",
            "serve",
            "--host",
            CDP_HOST,
            "--port",
            str(CDP_PORT),
        ]
        self._proc = subprocess.Popen(  # noqa: S603
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(CDP_STARTUP_DELAY)

    def _stop(self) -> None:
        if self._proc:
            self._proc.terminate()
            self._proc.wait()
            self._proc = None

    def render(self, url: str) -> str:
        """Render a URL with cookies injected and return the page HTML."""
        with sync_playwright() as p:
            browser = p.chromium.connect_over_cdp(
                f"ws://{CDP_HOST}:{CDP_PORT}",
            )
            context = browser.new_context()
            context.add_cookies(self._pw_cookies)  # type: ignore[arg-type]
            page = context.new_page()
            page.goto(url, wait_until="networkidle", timeout=RENDER_TIMEOUT)
            html = page.content()
            browser.close()
        return html

    def render_unauthenticated(self, url: str) -> str:
        """Render a URL without cookies via lightpanda fetch CLI."""
        cmd = ["lightpanda", "fetch", "--dump", "html", url]
        result = subprocess.run(  # noqa: S603
            cmd,
            capture_output=True,
            text=True,
            timeout=FETCH_TIMEOUT,
            check=False,
        )
        if result.returncode != 0:
            msg = f"Lightpanda fetch failed: {result.stderr}"
            raise RuntimeError(msg)
        return result.stdout

    def __enter__(self) -> Self:
        """Start the Lightpanda CDP server."""
        self._start()
        return self

    def __exit__(self, *_args: object) -> None:
        """Stop the Lightpanda CDP server."""
        self._stop()
