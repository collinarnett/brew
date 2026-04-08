"""Introspect clan CLI's argparse tree and dump as JSON.

Run at Nix build time to produce a static command tree that
the Haskell MCP server reads -- no runtime discovery needed.
"""

import argparse
import json
import sys
from dataclasses import asdict, dataclass, field
from functools import reduce


@dataclass
class Argument:
    name: str
    help: str
    required: bool
    positional: bool
    type: str
    flags: list[str] | None = None
    choices: list[str] | None = None
    array: bool | None = None
    default: str | None = None


@dataclass
class Command:
    path: list[str]
    description: str
    help_text: str
    arguments: list[Argument] = field(default_factory=list)


def action_to_argument(action):
    match action:
        case argparse._HelpAction() | argparse._SubParsersAction():
            return None
        case argparse._StoreTrueAction() | argparse._StoreFalseAction() | argparse.BooleanOptionalAction():
            ty = "boolean"
        case argparse._CountAction():
            ty = "integer"
        case _ if action.type is int:
            ty = "integer"
        case _ if action.type is float:
            ty = "number"
        case _ if action.choices:
            ty = "enum"
        case _:
            ty = "string"

    return Argument(
        name=action.dest,
        help=action.help or "",
        required=getattr(action, "required", False),
        positional=not bool(action.option_strings),
        type=ty,
        flags=list(action.option_strings) or None,
        choices=[str(c) for c in action.choices] if action.choices else None,
        array=True if action.nargs in ("*", "+", argparse.REMAINDER) else None,
        default=str(action.default) if action.default not in (None, argparse.SUPPRESS, False, []) else None,
    )


def dump_parser(parser, prefix=None):
    prefix = prefix or []
    subs = [a for a in (parser._subparsers._actions if parser._subparsers else [])
            if isinstance(a, argparse._SubParsersAction)]

    match subs:
        case []:
            args = [a for action in parser._actions if (a := action_to_argument(action)) is not None]
            return [Command(prefix, parser.description or "", parser.format_help(), args)]
        case actions:
            return reduce(list.__add__, [
                dump_parser(sub, prefix + [name])
                for action in actions
                for name, sub in action.choices.items()
                if len(name) > 2
            ], [])


def serialize(obj):
    return {k: v for k, v in asdict(obj).items() if v is not None}


if __name__ == "__main__":
    from clan_cli.cli import create_parser

    commands = [serialize(c) for c in dump_parser(create_parser()) if c.path]
    json.dump(commands, sys.stdout, indent=2)
    sys.stdout.write("\n")
