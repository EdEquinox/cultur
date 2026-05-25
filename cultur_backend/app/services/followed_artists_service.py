"""Backward-compatible import path; implementation lives in user_follow_service."""

from .user_follow_service import follow_artist, list_followed_artists, unfollow_artist

__all__ = ["follow_artist", "list_followed_artists", "unfollow_artist"]
