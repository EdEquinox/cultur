from __future__ import annotations

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from ..igdb_client import IgdbError
from ..omdb_client import OmdbError
from ..schemas import ErrorResponse
from ..tmdb_client import TmdbError
from ..yamtrack_client import YamtrackAuthExpired, YamtrackError


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(HTTPException)
    async def http_exception_handler(request, exc: HTTPException):  # type: ignore[override]
        return JSONResponse(
            status_code=exc.status_code,
            content=ErrorResponse(error=str(exc.detail)).model_dump(),
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request, exc: Exception):  # type: ignore[override]
        return JSONResponse(
            status_code=500,
            content=ErrorResponse(error=str(exc)).model_dump(),
        )

    @app.exception_handler(YamtrackAuthExpired)
    async def upstream_auth_handler(request, exc: YamtrackAuthExpired):  # type: ignore[override]
        return JSONResponse(
            status_code=401,
            content=ErrorResponse(error=str(exc)).model_dump(),
        )

    @app.exception_handler(YamtrackError)
    async def upstream_error_handler(request, exc: YamtrackError):  # type: ignore[override]
        return JSONResponse(
            status_code=502,
            content=ErrorResponse(error=str(exc)).model_dump(),
        )

    @app.exception_handler(requests.RequestException)
    async def requests_error_handler(request, exc: requests.RequestException):  # type: ignore[override]
        return JSONResponse(
            status_code=502,
            content=ErrorResponse(error=f"Legacy provider request failed: {exc}").model_dump(),
        )

    @app.exception_handler(TmdbError)
    async def tmdb_error_handler(request, exc: TmdbError):  # type: ignore[override]
        return JSONResponse(
            status_code=502,
            content=ErrorResponse(error=str(exc)).model_dump(),
        )

    @app.exception_handler(OmdbError)
    async def omdb_error_handler(request, exc: OmdbError):  # type: ignore[override]
        return JSONResponse(
            status_code=502,
            content=ErrorResponse(error=str(exc)).model_dump(),
        )

    @app.exception_handler(IgdbError)
    async def igdb_error_handler(request, exc: IgdbError):  # type: ignore[override]
        return JSONResponse(
            status_code=502,
            content=ErrorResponse(error=str(exc)).model_dump(),
        )

