"""Import Walmart order history into Grocy inventory."""

import argparse
import os
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

from .config import Config, GrocyConfig, ImportOptions
from .grocy import GrocyClient
from .service import ImportState, get_walmart_cookies, run_import, run_list

MIN_SINCE_PARTS = 2
MS_PER_SECOND = 1000


def parse_since(since_str: str) -> int:
    """Parse a relative time string like '3 days ago' into a unix timestamp (ms)."""
    parts = since_str.lower().strip().split()
    if len(parts) < MIN_SINCE_PARTS:
        msg = f"Cannot parse '{since_str}' — expected '<N> days/hours/weeks ago'"
        raise ValueError(msg)

    n = int(parts[0])
    unit = parts[1].rstrip("s")
    deltas = {
        "day": timedelta(days=n),
        "hour": timedelta(hours=n),
        "week": timedelta(weeks=n),
    }
    if unit not in deltas:
        msg = f"Unknown time unit: {parts[1]}"
        raise ValueError(msg)

    return int((datetime.now(tz=UTC) - deltas[unit]).timestamp() * MS_PER_SECOND)


def parse_config(args: argparse.Namespace) -> Config:
    """Build Config from CLI args and environment variables."""
    grocy_url = args.grocy_url or os.environ.get("GROCY_URL")
    grocy_api_key = args.grocy_api_key or os.environ.get("GROCY_API_KEY")

    if not grocy_url or not grocy_api_key:
        sys.stderr.write(
            "Error: --grocy-url and --grocy-api-key "
            "(or GROCY_URL/GROCY_API_KEY) required\n",
        )
        sys.exit(1)

    return Config(
        grocy=GrocyConfig(url=grocy_url, api_key=grocy_api_key),
        state_file=args.state_file,
    )


def cmd_list(args: argparse.Namespace) -> None:
    """List recent Walmart orders."""
    cookies = get_walmart_cookies()
    since = parse_since(args.since) if args.since else None

    summaries = run_list(cookies, since=since, limit=args.limit)

    for order in summaries:
        item_names = [i.name for i in order.items]
        item_preview = ", ".join(item_names[:3])
        remaining = len(item_names) - 3
        if remaining > 0:
            item_preview += f" (+{remaining} more)"

        sys.stdout.write(
            f"  {order.order_id}  {order.order_type:<15}"
            f" {order.item_count:>3} items  {order.status}\n",
        )
        if item_preview:
            sys.stdout.write(f"    {item_preview}\n")
        sys.stdout.write("\n")


def cmd_import(args: argparse.Namespace) -> None:
    """Import Walmart orders into Grocy inventory."""
    config = parse_config(args)
    cookies = get_walmart_cookies()
    grocy = GrocyClient(config.grocy.url, config.grocy.api_key)
    state = ImportState(Path(config.state_file))
    since = parse_since(args.since) if args.since else None

    options = ImportOptions(
        since=since,
        limit=args.limit,
        dry_run=args.dry_run,
        force=args.force,
    )
    results = run_import(grocy, state, cookies, options)

    prefix = "[DRY RUN] " if args.dry_run else ""
    total_matched = sum(len(r.matched) for r in results)
    total_unmatched = sum(len(r.unmatched) for r in results)

    for result in results:
        sys.stdout.write(f"\n  Order {result.order_id}:\n")
        for m in result.matched:
            price = (
                f" ${m.walmart_item.line_price:.2f}"
                if m.walmart_item.line_price
                else ""
            )
            sys.stdout.write(
                f"    + {m.walmart_item.name}{price}"
                f" -> {m.grocy_product.name}"
                f" (score: {m.score})\n",
            )
        for item in result.unmatched:
            price = (
                f" (${item.line_price:.2f})" if item.line_price else ""
            )
            sys.stdout.write(
                f"    ? {item.name}{price} (no match)\n",
            )

    sys.stdout.write(
        f"\n{prefix}Import complete:"
        f" {total_matched} matched,"
        f" {total_unmatched} unmatched\n",
    )

    if total_unmatched:
        sys.stdout.write(
            "\nUnmatched items (create these in Grocy first):\n",
        )
        for result in results:
            for item in result.unmatched:
                price = (
                    f" (${item.line_price:.2f})" if item.line_price else ""
                )
                sys.stdout.write(f"  - {item.name}{price}\n")


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Import Walmart order history into Grocy inventory",
    )
    parser.add_argument(
        "--grocy-url",
        default=None,
        help="Grocy instance URL (or GROCY_URL env var)",
    )
    parser.add_argument(
        "--grocy-api-key",
        default=None,
        help="Grocy API key (or GROCY_API_KEY env var)",
    )
    parser.add_argument(
        "--state-file",
        default=str(
            Path.home() / ".local/share/walmart-grocy-import/state.json",
        ),
        help="Path to state file tracking imported orders",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser(
        "list",
        help="List recent Walmart orders",
    )
    list_parser.add_argument(
        "--since",
        help="Time filter, e.g. '7 days ago'",
    )
    list_parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Max orders to fetch",
    )

    import_parser = subparsers.add_parser(
        "import",
        help="Import orders into Grocy",
    )
    import_parser.add_argument(
        "--since",
        help="Time filter, e.g. '3 days ago'",
    )
    import_parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Max orders to fetch",
    )
    import_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be imported",
    )
    import_parser.add_argument(
        "--force",
        action="store_true",
        help="Re-import already imported orders",
    )

    args = parser.parse_args()

    if args.command == "list":
        cmd_list(args)
    elif args.command == "import":
        cmd_import(args)
