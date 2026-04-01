"""Extract persisted query hashes from Walmart's frontend JavaScript.

Uses Lightpanda to render the page (bypassing bot detection), then fetches
the webpack JS chunks from Walmart's CDN to find the current hashes.
"""

import re
import subprocess

import requests

WALMART_BASE = "https://www.walmart.com"

OPERATIONS = {
    "PurchaseHistoryV2": "/orchestra/cph/graphql/PurchaseHistoryV2/",
}

HASH_PATTERN = re.compile(r'name:"(\w+)",hash:"([0-9a-f]{64})"')
SCRIPT_PATTERN = re.compile(r'src="(https://i5\.walmartimages\.com[^"]+\.js)"')


def resolve_endpoints() -> dict[str, str]:
    """Discover current Walmart GraphQL endpoint URLs.

    Returns a dict mapping operation name -> full URL.
    """
    result = subprocess.run(
        ["lightpanda", "fetch", "--dump", "html", f"{WALMART_BASE}/orders"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Lightpanda failed: {result.stderr}")

    script_urls = SCRIPT_PATTERN.findall(result.stdout)

    resolved: dict[str, str] = {}
    remaining = set(OPERATIONS.keys())

    for url in script_urls:
        if not remaining:
            break

        resp = requests.get(url, timeout=15)
        if resp.status_code != 200:
            continue

        for name, query_hash in HASH_PATTERN.findall(resp.text):
            if name in remaining:
                resolved[name] = f"{WALMART_BASE}{OPERATIONS[name]}{query_hash}"
                remaining.discard(name)

    if remaining:
        raise RuntimeError(f"Could not find hashes for: {', '.join(remaining)}")

    return resolved
