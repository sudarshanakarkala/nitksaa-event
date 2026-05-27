from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    app_env: str = "development"
    app_name: str = "NITKSAA Event API"
    app_version: str = "0.1.0-alpha"

    # events_db connection
    events_db_url: str = "postgresql://postgres:postgres@localhost:5432/events_db"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache
def get_settings() -> Settings:
    return Settings()
