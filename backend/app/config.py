from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra='ignore')
    database_url: str
    jwt_secret: str = Field(min_length=48)
    cors_origins: list[str]
    token_ttl_seconds: int = Field(default=604800, ge=60, le=604800)
    auth_rate_limit: int = Field(default=10, ge=1, le=100)
    auth_rate_window_seconds: int = Field(default=300, ge=1, le=3600)
    attachment_storage_path: str = '/data/attachments'
    vapid_public_key: str | None = None
    vapid_private_key: str | None = None
    vapid_subject: str | None = None

    @field_validator('database_url')
    @classmethod
    def postgres_only(cls, value):
        if not value.startswith('postgresql+psycopg://'):
            raise ValueError('PostgreSQL psycopg URL required')
        return value

    @field_validator('cors_origins')
    @classmethod
    def explicit_origins(cls, values):
        from urllib.parse import urlsplit
        for value in values:
            parsed = urlsplit(value)
            if '*' in value or parsed.scheme not in ('http', 'https') or not parsed.netloc or parsed.path or parsed.query or parsed.fragment or parsed.username:
                raise ValueError('Explicit HTTP origins only')
        return values
