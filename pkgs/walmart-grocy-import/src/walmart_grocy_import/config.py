"""Application configuration."""

from pydantic import BaseModel


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
