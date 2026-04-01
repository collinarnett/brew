"""Application configuration and shared constants."""

from pydantic import BaseModel

WALMART_BASE = "https://www.walmart.com"
REQUEST_TIMEOUT = 15


class GrocyConfig(BaseModel):
    """Connection settings for the Grocy REST API."""

    url: str
    api_key: str


class ImportOptions(BaseModel):
    """Options for the import command."""

    since: int | None = None
    limit: int = 10
    dry_run: bool = False
    force: bool = False


class Config(BaseModel):
    """Top-level application configuration."""

    grocy: GrocyConfig
    state_file: str
