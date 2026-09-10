from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from app.config import Settings

settings = Settings()
engine = create_engine(settings.database_url, pool_pre_ping=True, connect_args={'connect_timeout': 5})
SessionLocal = sessionmaker(engine, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

def get_db():
    with SessionLocal() as db:
        yield db
