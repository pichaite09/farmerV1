from datetime import date, datetime, timezone, timedelta
import uuid
from typing import Literal
import jwt
from argon2 import PasswordHasher
from fastapi import FastAPI, Depends, HTTPException, Response, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from argon2.exceptions import VerifyMismatchError, VerificationError
from app.errors import install_errors
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy.orm import Session
from app.database import settings, get_db
from app.models import User, AuthSession
from app.throttle import throttle
from sqlalchemy import text
from app.database import engine

app = FastAPI(title='Farmer-main API', version='1.0.0-phase1')
install_errors(app)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"], allow_headers=["Authorization", "Content-Type"], allow_credentials=False)
password_hasher = PasswordHasher()
dummy_hash = password_hasher.hash('unusable-dummy-verification-password')
bearer = HTTPBearer(auto_error=False)


class Credentials(BaseModel):
    model_config = ConfigDict(extra='forbid')
    email: EmailStr
    password: str = Field(min_length=8, max_length=200)

    @field_validator('email', mode='before')
    @classmethod
    def normalize_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value

class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    email: str
    role: Literal['farmer', 'admin']
    first_name: str | None = None
    last_name: str | None = None
    birth_date: date | None = None
    house_number: str | None = None
    subdistrict: str | None = None
    district: str | None = None
    province: str | None = None
    phone: str | None = None

class UserProfilePatch(BaseModel):
    model_config = ConfigDict(
        alias_generator=lambda s: ''.join([s.split('_')[0]] + [p.title() for p in s.split('_')[1:]]),
        populate_by_name=True,
        extra='forbid',
    )
    first_name: str | None = Field(default=None, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    birth_date: date | None = None
    house_number: str | None = Field(default=None, max_length=100)
    subdistrict: str | None = Field(default=None, max_length=150)
    district: str | None = Field(default=None, max_length=150)
    province: str | None = Field(default=None, max_length=150)
    phone: str | None = Field(default=None, max_length=30)

    @field_validator('*', mode='before')
    @classmethod
    def trim_text(cls, value):
        return value.strip() if isinstance(value, str) else value

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = 'bearer'
    user: UserResponse

def issue_session(user, db):
    now = datetime.now(timezone.utc).replace(microsecond=0)
    session = AuthSession(user_id=user.id, created_at=now, expires_at=now + timedelta(seconds=settings.token_ttl_seconds))
    db.add(session)
    db.flush()
    token = jwt.encode({'sub': str(user.id), 'jti': str(session.id), 'iat': int(now.timestamp()), 'nbf': int(now.timestamp()), 'exp': int(session.expires_at.timestamp()), 'iss': 'farmer-main', 'aud': 'farmer-main-api'}, settings.jwt_secret, algorithm='HS256')
    db.commit()
    return TokenResponse(access_token=token, user=UserResponse.model_validate(user))

@app.post('/api/v1/auth/register', status_code=201, response_model=TokenResponse)
def register(body: Credentials, request: Request, db: Session = Depends(get_db)):
    throttle(request, str(body.email))
    user = User(email=str(body.email), password_hash=password_hasher.hash(body.password), role='farmer')
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Email already registered')
    return issue_session(user, db)


def unauthorized():
    return HTTPException(401, 'Invalid or expired session', headers={'WWW-Authenticate': 'Bearer'})


def current_session(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)):
    if credentials is None:
        raise unauthorized()
    try:
        claims = jwt.decode(credentials.credentials, settings.jwt_secret, algorithms=['HS256'], audience='farmer-main-api', issuer='farmer-main', options={'require': ['sub', 'jti', 'iat', 'nbf', 'exp', 'iss', 'aud']})
        session_id = uuid.UUID(claims['jti'])
        user_id = uuid.UUID(claims['sub'])
    except (jwt.InvalidTokenError, ValueError, TypeError, KeyError, AttributeError):
        raise unauthorized()
    session = db.get(AuthSession, session_id)
    if session is None or session.user_id != user_id or session.revoked_at is not None or session.expires_at <= datetime.now(timezone.utc):
        raise unauthorized()
    user = db.get(User, user_id)
    if user is None or user.role not in ('farmer', 'admin') or user.status != 'active':
        raise unauthorized()
    return session, user

def farmer_session(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db: Session = Depends(get_db)):
    identity = current_session(credentials, db)
    if identity[1].role != 'farmer':
        raise HTTPException(403, 'Farmer access required')
    return identity

def admin_session(identity=Depends(current_session)):
    if identity[1].role != 'admin':
        raise HTTPException(403, 'Admin access required')
    return identity


@app.post('/api/v1/auth/login', response_model=TokenResponse)
def login(body: Credentials, request: Request, db: Session = Depends(get_db)):
    throttle(request, str(body.email))
    user = db.scalar(select(User).where(User.email == str(body.email)))
    try:
        password_hasher.verify(user.password_hash if user else dummy_hash, body.password)
    except (VerifyMismatchError, VerificationError):
        raise unauthorized()
    if user is None or user.role not in ('farmer', 'admin') or user.status != 'active':
        raise unauthorized()
    return issue_session(user, db)


@app.get('/api/v1/auth/me', response_model=UserResponse)
def me(identity=Depends(current_session)):
    return UserResponse.model_validate(identity[1])


@app.patch('/api/v1/auth/me', response_model=UserResponse)
def update_me(body: UserProfilePatch, identity=Depends(current_session), db: Session = Depends(get_db)):
    user = identity[1]
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(user, key, value)
    db.commit()
    db.refresh(user)
    return UserResponse.model_validate(user)

@app.post('/api/v1/auth/logout', status_code=204)
def logout(identity=Depends(current_session), db: Session = Depends(get_db)):
    identity[0].revoked_at = datetime.now(timezone.utc)
    db.commit()
    return Response(status_code=204)

@app.get('/health/live')
def live():
    return {'status': 'ok'}

@app.get('/health/ready')
@app.get('/health')
def ready():
    try:
        with engine.connect() as conn:
            assert conn.execute(text('SELECT version_num FROM alembic_version')).scalar_one() == '0024_announce_attach'
            conn.execute(text('SELECT id FROM users LIMIT 1'))
    except Exception:
        raise HTTPException(503, 'Database not ready')
    return {'status': 'ok', 'database': 'ok'}

from app.resources import router as resources_router
app.include_router(resources_router)
from app.phase3 import router as phase3_router
app.include_router(phase3_router)
from app.reports import router as reports_router
app.include_router(reports_router)
from app.attachments import router as attachments_router
app.include_router(attachments_router)
from app.notifications import router as notifications_router
app.include_router(notifications_router)
from app.push import router as push_router
app.include_router(push_router)
from app.devices import router as devices_router
app.include_router(devices_router)
from app.field_inspections import router as field_inspections_router
app.include_router(field_inspections_router)
from app.admin import router as admin_router
app.include_router(admin_router)
