"""Lightpanda browser lifecycle and page rendering."""

import subprocess
import time
import urllib.request
from typing import Self

from playwright.sync_api import sync_playwright

from .config import REQUEST_TIMEOUT

CDP_HOST = "127.0.0.1"
CDP_PORT = 9222
CDP_POLL_INTERVAL = 0.1
CDP_POLL_ATTEMPTS = 30
RENDER_TIMEOUT = 30000


def _cdp_is_ready(url: str) -> bool:
    """Check if the CDP server is accepting connections."""
    try:
        urllib.request.urlopen(url, timeout=1)  # noqa: S310
    except OSError:
        return False
    return True


def _wait_for_cdp(host: str, port: int) -> None:
    """Poll the CDP HTTP endpoint until the server is accepting connections."""
    url = f"http://{host}:{port}/json/version"
    for _ in range(CDP_POLL_ATTEMPTS):
        if _cdp_is_ready(url):
            return
        time.sleep(CDP_POLL_INTERVAL)
    msg = f"Lightpanda CDP server failed to start on {host}:{port}"
    raise RuntimeError(msg)


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
        _wait_for_cdp(CDP_HOST, CDP_PORT)

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
            page.goto(
                url,
                wait_until="networkidle",
                timeout=RENDER_TIMEOUT,
            )
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
            timeout=REQUEST_TIMEOUT,
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
