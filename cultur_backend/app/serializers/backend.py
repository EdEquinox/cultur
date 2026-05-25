from __future__ import annotations

from datetime import datetime
from typing import Any

from ..backend_models import AppUser, MediaItem, TrackingEntry
from ..schemas import BackendMediaResponse, BackendTrackingResponse, BackendUserResponse


def serialize_user(user: AppUser) -> BackendUserResponse:
    return BackendUserResponse(
        id=user.id,
        username=user.username,
        displayName=user.display_name,
    )


def serialize_media_item(item: MediaItem) -> BackendMediaResponse:
    return BackendMediaResponse(
        id=item.id,
        source=item.source,
        externalId=item.external_id,
        mediaType=item.media_type,
        title=item.title,
        subtitle=item.subtitle,
        description=item.description,
        imageUrl=item.image_url,
        metadata=item.provider_payload or {},
    )


def serialize_media_item_with_overlay(
    item: MediaItem,
    *,
    metadata_overlay: dict[str, Any] | None = None,
    subtitle: str | None = None,
) -> BackendMediaResponse:
    base = serialize_media_item(item)
    merged_meta = {**base.metadata, **(metadata_overlay or {})}
    updates: dict[str, Any] = {"metadata": merged_meta}
    if subtitle is not None:
        updates["subtitle"] = subtitle
    return base.model_copy(update=updates)


def _iso_z_optional(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.isoformat().replace("+00:00", "Z")


def serialize_tracking_entry(
    entry: TrackingEntry,
    user: AppUser,
    media_item: MediaItem,
    *,
    episode_watched_count: int = 0,
) -> BackendTrackingResponse:
    return BackendTrackingResponse(
        id=entry.id,
        username=user.username,
        media=serialize_media_item(media_item),
        status=entry.status,
        progress=entry.progress,
        score=entry.score,
        notes=entry.notes,
        completedAt=_iso_z_optional(entry.completed_at),
        startedAt=_iso_z_optional(entry.started_at),
        droppedAt=_iso_z_optional(entry.dropped_at),
        collectedAt=_iso_z_optional(entry.collected_at),
        createdAt=entry.created_at.isoformat().replace("+00:00", "Z"),
        updatedAt=entry.updated_at.isoformat().replace("+00:00", "Z"),
        episodeWatchedCount=episode_watched_count,
        tvFullyWatched=bool(entry.tv_fully_watched),
        tvAiredEpisodeTotal=entry.tv_aired_episode_total,
    )
