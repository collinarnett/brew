"""Import Walmart order history into Grocy inventory."""

import argparse
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

from .config import Config, GrocyConfig
from .grocy import GrocyClient
from .service import ImportState, get_walmart_cookies, run_import, run_list


def parse_since(since_str: str) -> int:
    """Parse a relative time string like '3 days ago' into a unix timestamp (ms)."""
    parts = since_str.lower().strip().split()
    if len(parts) < 2:
        raise ValueError(f"Cannot parse '{since_str}' — expected '<N> days/hours/weeks ago'")

    n = int(parts[0])
    unit = parts[1].rstrip("s")
    deltas = {"day": timedelta(days=n), "hour": timedelta(hours=n), "week": timedelta(weeks=n)}
    if unit not in deltas:
        raise ValueError(f"Unknown time unit: {parts[1]}")

    return int((datetime.now() - deltas[unit]).timestamp() * 1000)


def parse_config(args: argparse.Namespace) -> Config:
    grocy_url = args.grocy_url or os.environ.get("GROCY_URL")
    grocy_api_key = args.grocy_api_key or os.environ.get("GROCY_API_KEY")

    if args.command == "import" and (not grocy_url or not grocy_api_key):
        print("Error: --grocy-url and --grocy-api-key (or GROCY_URL/GROCY_API_KEY) required", file=sys.stderr)
        sys.exit(1)

    return Config(
        grocy=GrocyConfig(url=grocy_url or "", api_key=grocy_api_key or ""),
        state_file=args.state_file,
    )


def cmd_list(args: argparse.Namespace) -> None:
    req_cookies, pw_cookies = get_walmart_cookies()
    since = parse_since(args.since) if args.since else None

    summaries = run_list(req_cookies, pw_cookies, since=since, limit=args.limit)

    for order in summaries:
        item_names = [i.name for i in order.items]
        item_preview = ", ".join(item_names[:3])
        if len(item_names) > 3:
            item_preview += f" (+{len(item_names) - 3} more)"

        print(f"  {order.order_id}  {order.order_type:<15} {order.item_count:>3} items  {order.status}")
        if item_preview:
            print(f"    {item_preview}")
        print()


def cmd_import(args: argparse.Namespace) -> None:
    config = parse_config(args)
    req_cookies, pw_cookies = get_walmart_cookies()
    grocy = GrocyClient(config.grocy.url, config.grocy.api_key)
    state = ImportState(Path(config.state_file))
    since = parse_since(args.since) if args.since else None

    results = run_import(
        grocy,
        state,
        req_cookies,
        pw_cookies,
        since=since,
        limit=args.limit,
        dry_run=args.dry_run,
        force=args.force,
    )

    prefix = "[DRY RUN] " if args.dry_run else ""
    total_matched = sum(len(r.matched) for r in results)
    total_unmatched = sum(len(r.unmatched) for r in results)

    for result in results:
        print(f"\n  Order {result.order_id}:")
        for m in result.matched:
            price = f" ${m.walmart_item.line_price:.2f}" if m.walmart_item.line_price else ""
            print(f"    + {m.walmart_item.name}{price} -> {m.grocy_product.name} (score: {m.score})")
        for item in result.unmatched:
            price = f" (${item.line_price:.2f})" if item.line_price else ""
            print(f"    ? {item.name}{price} (no match)")

    print(f"\n{prefix}Import complete: {total_matched} matched, {total_unmatched} unmatched")

    if total_unmatched:
        print("\nUnmatched items (create these in Grocy first):")
        for result in results:
            for item in result.unmatched:
                price = f" (${item.line_price:.2f})" if item.line_price else ""
                print(f"  - {item.name}{price}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Import Walmart order history into Grocy inventory")
    parser.add_argument("--grocy-url", default=None, help="Grocy instance URL (or GROCY_URL env var)")
    parser.add_argument("--grocy-api-key", default=None, help="Grocy API key (or GROCY_API_KEY env var)")
    parser.add_argument(
        "--state-file",
        default=str(Path.home() / ".local/share/walmart-grocy-import/state.json"),
        help="Path to state file tracking imported orders",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List recent Walmart orders")
    list_parser.add_argument("--since", help="Time filter, e.g. '7 days ago'")
    list_parser.add_argument("--limit", type=int, default=10, help="Max orders to fetch")

    import_parser = subparsers.add_parser("import", help="Import orders into Grocy")
    import_parser.add_argument("--since", help="Time filter, e.g. '3 days ago'")
    import_parser.add_argument("--limit", type=int, default=10, help="Max orders to fetch")
    import_parser.add_argument("--dry-run", action="store_true", help="Show what would be imported")
    import_parser.add_argument("--force", action="store_true", help="Re-import already imported orders")

    args = parser.parse_args()

    if args.command == "list":
        cmd_list(args)
    elif args.command == "import":
        cmd_import(args)
