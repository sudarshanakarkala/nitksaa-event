"""API docs (/docs, /redoc, /openapi.json) are off in production unless
DOCS_ENABLED says otherwise, and on everywhere else."""

from app.config import Settings


def _settings(**env) -> Settings:
    return Settings(_env_file=None, **env)


def test_docs_on_in_development():
    assert _settings(APP_ENV="development").docs_enabled is True


def test_docs_off_in_production():
    assert _settings(APP_ENV="production").docs_enabled is False


def test_docs_can_be_switched_on_in_production():
    assert _settings(APP_ENV="production", DOCS_ENABLED=True).docs_enabled is True


def test_docs_can_be_switched_off_elsewhere():
    assert _settings(APP_ENV="development", DOCS_ENABLED=False).docs_enabled is False
