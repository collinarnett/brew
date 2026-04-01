"""Application configuration."""

from pydantic import BaseModel


class GrocyConfig(BaseModel):
    url: str
    api_key: str


class Config(BaseModel):
    grocy: GrocyConfig
    state_file: str
