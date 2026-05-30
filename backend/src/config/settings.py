from pathlib import Path
from pydantic_settings import BaseSettings
from pydantic import Field

# backend/src/config/settings.py → up 3 levels → backend/
_ENV_FILE = Path(__file__).parent.parent.parent / ".env"


class Settings(BaseSettings):
    # Database
    db_host: str = Field("127.0.0.1", alias="DB_HOST")
    db_port: int = Field(5432, alias="DB_PORT")
    db_name: str = Field("website_db", alias="DB_NAME")
    alumni_db_name: str = Field("alumni_db", alias="ALUMNI_DB_NAME")
    db_user: str = Field("app_user", alias="DB_USER")
    db_password: str = Field(..., alias="DB_PASSWORD")
    db_sslmode: str = Field("require", alias="DB_SSLMODE")

    # Auth (JWT signing)
    secret_key: str = Field(..., alias="SECRET_KEY")
    access_token_expire_minutes: int = Field(480, alias="ACCESS_TOKEN_EXPIRE_MINUTES")

    # App
    app_env: str = Field("development", alias="APP_ENV")
    allowed_origins: str = Field("http://localhost:5173", alias="ALLOWED_ORIGINS")
    app_base_url: str = Field("http://localhost:5173", alias="APP_BASE_URL")

    # Email
    gmail_app_password: str = Field("", alias="GMAIL_APP_PASSWORD")

    # Notifications
    notify_webhook_url: str | None = Field(None, alias="NOTIFY_WEBHOOK_URL")

    # Firebase
    firebase_project_id: str = Field(
        "project-d22bed42-f302-4e23-8dc",
        alias="FIREBASE_PROJECT_ID",
    )

    @property
    def db_url(self) -> str:
        if self.app_env == "production":
            socket_dir = "/cloudsql/project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db"
            return f"postgresql://{self.db_user}:{self.db_password}@/{self.db_name}?host={socket_dir}"
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"

    @property
    def alumni_db_url(self) -> str:
        if self.app_env == "production":
            socket_dir = "/cloudsql/project-d22bed42-f302-4e23-8dc:asia-south1:nitksaa-alumni-db"
            return f"postgresql://{self.db_user}:{self.db_password}@/{self.alumni_db_name}?host={socket_dir}"
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.alumni_db_name}"

    @property
    def origins_list(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",")]

    class Config:
        env_file = _ENV_FILE
        populate_by_name = True


settings = Settings()
