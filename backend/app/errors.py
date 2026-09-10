import uuid
from fastapi import Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException


def install_errors(app):
    @app.middleware('http')
    async def request_metadata(request: Request, call_next):
        request.state.request_id = str(uuid.uuid4())
        response = await call_next(request)
        response.headers['X-Request-ID'] = request.state.request_id
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        code = {401: 'unauthorized', 404: 'not_found', 409: 'conflict', 422: 'validation_error', 429: 'rate_limited', 503: 'unavailable'}.get(exc.status_code, 'request_error')
        return JSONResponse(status_code=exc.status_code, content={'code': code, 'message': str(exc.detail), 'fieldErrors': {}, 'requestId': request.state.request_id}, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        fields = {'.'.join(str(part) for part in e['loc'][1:]): e['msg'] for e in exc.errors()}
        return JSONResponse(status_code=422, content={'code': 'validation_error', 'message': 'Invalid request', 'fieldErrors': fields, 'requestId': request.state.request_id})

    @app.exception_handler(Exception)
    async def internal_error(request, exc):
        return JSONResponse(status_code=500, content={'code': 'internal_error', 'message': 'Internal server error', 'fieldErrors': {}, 'requestId': getattr(request.state, 'request_id', str(uuid.uuid4()))})
