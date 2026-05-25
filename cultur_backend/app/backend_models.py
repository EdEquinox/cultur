from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def _utc_now() -> datetime:
    return datetime.now(tz=UTC)


def _new_id() -> str:
    return str(uuid4())


class AppUser(Base):
    __tablename__ = "app_users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    tracking_entries: Mapped[list["TrackingEntry"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    tv_episode_watches: Mapped[list["TvEpisodeWatch"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    tv_episode_user_states: Mapped[list["TvEpisodeUserState"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    tv_season_user_states: Mapped[list["TvSeasonUserState"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    native_sessions: Mapped[list["NativeSession"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    user_follows: Mapped[list["UserFollow"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    collections: Mapped[list["Collection"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )


class NativeSession(Base):
    __tablename__ = "native_sessions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    access_token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    access_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    refresh_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    user: Mapped[AppUser] = relationship(back_populates="native_sessions")


class CatalogSource(Base):
    __tablename__ = "catalog_sources"

    code: Mapped[str] = mapped_column(String(64), primary_key=True)
    label: Mapped[str | None] = mapped_column(String(128), nullable=True)


class CatalogItem(Base):
    """Canonical catalog row (formerly media_items)."""

    __tablename__ = "catalog_items"
    __table_args__ = (
        UniqueConstraint(
            "source_code",
            "media_type",
            "external_id",
            name="uq_catalog_items_source_type_external",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    source: Mapped[str] = mapped_column("source_code", String(64), index=True)
    external_id: Mapped[str] = mapped_column(String(128), index=True)
    media_type: Mapped[str] = mapped_column(String(32), index=True)
    title: Mapped[str] = mapped_column(String(255))
    subtitle: Mapped[str | None] = mapped_column(String(255), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    provider_payload: Mapped[dict[str, object]] = mapped_column(JSON, default=dict)
    is_pending: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    tracking_entries: Mapped[list["TrackingEntry"]] = relationship(
        back_populates="media_item",
        cascade="all, delete-orphan",
    )
    tv_episode_watches: Mapped[list["TvEpisodeWatch"]] = relationship(
        back_populates="media_item",
        cascade="all, delete-orphan",
    )
    tv_episode_user_states: Mapped[list["TvEpisodeUserState"]] = relationship(
        back_populates="media_item",
        cascade="all, delete-orphan",
    )
    tv_season_user_states: Mapped[list["TvSeasonUserState"]] = relationship(
        back_populates="media_item",
        cascade="all, delete-orphan",
    )


MediaItem = CatalogItem


class Person(Base):
    __tablename__ = "people"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    entity_kind: Mapped[str] = mapped_column(String(32), index=True)
    display_name: Mapped[str] = mapped_column(String(255))
    biography: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    known_for: Mapped[str | None] = mapped_column(String(255), nullable=True)
    birth_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    death_date: Mapped[str | None] = mapped_column(String(32), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    identities: Mapped[list["PersonIdentity"]] = relationship(
        back_populates="person",
        cascade="all, delete-orphan",
    )
    user_follows: Mapped[list["UserFollow"]] = relationship(
        back_populates="person",
        cascade="all, delete-orphan",
    )


class PersonIdentity(Base):
    __tablename__ = "person_identities"
    __table_args__ = (
        UniqueConstraint(
            "source_code",
            "external_id",
            name="uq_person_identities_source_external",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    person_id: Mapped[str] = mapped_column(
        ForeignKey("people.id", ondelete="CASCADE"),
        index=True,
    )
    source_code: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("catalog_sources.code"),
        index=True,
    )
    external_id: Mapped[str] = mapped_column(String(255), index=True)

    person: Mapped[Person] = relationship(back_populates="identities")


class UserFollow(Base):
    __tablename__ = "user_follows"
    __table_args__ = (
        UniqueConstraint("user_id", "person_id", name="uq_user_follows_user_person"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    person_id: Mapped[str] = mapped_column(
        ForeignKey("people.id", ondelete="CASCADE"),
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)

    user: Mapped[AppUser] = relationship(back_populates="user_follows")
    person: Mapped[Person] = relationship(back_populates="user_follows")


class TrackingEntry(Base):
    __tablename__ = "tracking_entries"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "catalog_item_id",
            name="uq_tracking_entries_user_catalog",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    media_item_id: Mapped[str] = mapped_column(
        "catalog_item_id",
        ForeignKey("catalog_items.id", ondelete="CASCADE"),
        index=True,
    )
    status: Mapped[str] = mapped_column(String(32), default="In progress")
    progress: Mapped[int | None] = mapped_column(Integer, nullable=True)
    tv_fully_watched: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    tv_aired_episode_total: Mapped[int | None] = mapped_column(Integer, nullable=True)
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    dropped_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    collected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    user: Mapped[AppUser] = relationship(back_populates="tracking_entries")
    media_item: Mapped[CatalogItem] = relationship(back_populates="tracking_entries")
    flags: Mapped[list["TrackingFlag"]] = relationship(
        back_populates="tracking_entry",
        cascade="all, delete-orphan",
    )
    collected_detail: Mapped["TrackingCollectedDetail | None"] = relationship(
        back_populates="tracking_entry",
        cascade="all, delete-orphan",
        uselist=False,
    )
    loans: Mapped[list["TrackingLoan"]] = relationship(
        back_populates="tracking_entry",
        cascade="all, delete-orphan",
    )


class TrackingFlag(Base):
    __tablename__ = "tracking_flags"
    __table_args__ = (
        UniqueConstraint("tracking_entry_id", "flag", name="uq_tracking_flags_entry_flag"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    tracking_entry_id: Mapped[str] = mapped_column(
        ForeignKey("tracking_entries.id", ondelete="CASCADE"),
        index=True,
    )
    flag: Mapped[str] = mapped_column(String(32), index=True)

    tracking_entry: Mapped[TrackingEntry] = relationship(back_populates="flags")


class TrackingCollectedDetail(Base):
    __tablename__ = "tracking_collected_details"

    tracking_entry_id: Mapped[str] = mapped_column(
        ForeignKey("tracking_entries.id", ondelete="CASCADE"),
        primary_key=True,
    )
    price: Mapped[str | None] = mapped_column(String(64), nullable=True)
    owned_release_source: Mapped[str | None] = mapped_column(String(32), nullable=True)
    owned_release_external_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    tracking_entry: Mapped[TrackingEntry] = relationship(back_populates="collected_detail")


class TrackingLoan(Base):
    __tablename__ = "tracking_loans"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    tracking_entry_id: Mapped[str] = mapped_column(
        ForeignKey("tracking_entries.id", ondelete="CASCADE"),
        index=True,
    )
    borrower_name: Mapped[str] = mapped_column(String(255))
    lent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    returned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    tracking_entry: Mapped[TrackingEntry] = relationship(back_populates="loans")


class Collection(Base):
    __tablename__ = "collections"
    __table_args__ = (
        UniqueConstraint("user_id", "media_type", "name", name="uq_collections_user_media_name"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255))
    media_type: Mapped[str] = mapped_column(String(32), index=True)
    slug: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_builtin: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    user: Mapped[AppUser] = relationship(back_populates="collections")
    items: Mapped[list["CollectionItem"]] = relationship(
        back_populates="collection",
        cascade="all, delete-orphan",
    )


class CollectionItem(Base):
    __tablename__ = "collection_items"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    collection_id: Mapped[str] = mapped_column(
        ForeignKey("collections.id", ondelete="CASCADE"),
        index=True,
    )
    catalog_item_id: Mapped[str] = mapped_column(
        ForeignKey("catalog_items.id", ondelete="CASCADE"),
        index=True,
    )
    season_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    episode_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sort_order: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)

    collection: Mapped[Collection] = relationship(back_populates="items")
    catalog_item: Mapped[CatalogItem] = relationship()


class TvEpisodeWatch(Base):
    __tablename__ = "tv_episode_watches"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "catalog_item_id",
            "season_number",
            "episode_number",
            name="uq_tv_episode_watch_user_series_ep",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    media_item_id: Mapped[str] = mapped_column(
        "catalog_item_id",
        ForeignKey("catalog_items.id", ondelete="CASCADE"),
        index=True,
    )
    season_number: Mapped[int] = mapped_column(Integer, index=True)
    episode_number: Mapped[int] = mapped_column(Integer, index=True)
    watched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    user: Mapped[AppUser] = relationship(back_populates="tv_episode_watches")
    media_item: Mapped[CatalogItem] = relationship(back_populates="tv_episode_watches")


class TvEpisodeUserState(Base):
    __tablename__ = "tv_episode_user_states"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "catalog_item_id",
            "season_number",
            "episode_number",
            name="uq_tv_episode_user_state_ep",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    media_item_id: Mapped[str] = mapped_column(
        "catalog_item_id",
        ForeignKey("catalog_items.id", ondelete="CASCADE"),
        index=True,
    )
    season_number: Mapped[int] = mapped_column(Integer, index=True)
    episode_number: Mapped[int] = mapped_column(Integer, index=True)
    rating: Mapped[float | None] = mapped_column(Float, nullable=True)
    rating_rated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    watchlist: Mapped[bool] = mapped_column(Boolean, default=False)
    watchlisted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    user: Mapped[AppUser] = relationship(back_populates="tv_episode_user_states")
    media_item: Mapped[CatalogItem] = relationship(back_populates="tv_episode_user_states")


class TvSeasonUserState(Base):
    __tablename__ = "tv_season_user_states"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "catalog_item_id",
            "season_number",
            name="uq_tv_season_user_state",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_id)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("app_users.id", ondelete="CASCADE"),
        index=True,
    )
    media_item_id: Mapped[str] = mapped_column(
        "catalog_item_id",
        ForeignKey("catalog_items.id", ondelete="CASCADE"),
        index=True,
    )
    season_number: Mapped[int] = mapped_column(Integer, index=True)
    rating: Mapped[float | None] = mapped_column(Float, nullable=True)
    rating_rated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    watchlist: Mapped[bool] = mapped_column(Boolean, default=False)
    watchlisted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )

    user: Mapped[AppUser] = relationship(back_populates="tv_season_user_states")
    media_item: Mapped[CatalogItem] = relationship(back_populates="tv_season_user_states")


class StashGameEventRow(Base):
    __tablename__ = "stash_game_events"

    slug: Mapped[str] = mapped_column(String(160), primary_key=True)
    title: Mapped[str] = mapped_column(String(512))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    image_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    stash_url: Mapped[str] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )


class StashEventsSyncMeta(Base):
    __tablename__ = "stash_events_sync_meta"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default="default")
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    event_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utc_now,
        onupdate=_utc_now,
    )
