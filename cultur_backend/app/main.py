from __future__ import annotations

from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.errors import register_exception_handlers
from .api.routers import auth, backend, catalog, health, legacy
from .config import load_settings
from .database import DatabaseManager
from .storage import SessionStore


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = load_settings()
    app.state.settings = settings
    app.state.database = DatabaseManager(settings)
    app.state.database.initialize()
    app.state.store = SessionStore(settings)
    yield


app = FastAPI(
    title="cult.u.r API",
    version="1.0.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

register_exception_handlers(app)

app.include_router(health.router)
app.include_router(backend.router)
app.include_router(catalog.router)
app.include_router(auth.router)
app.include_router(legacy.router)


def run() -> None:
    settings = load_settings()
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=False,
    )


if __name__ == "__main__":
    run()
