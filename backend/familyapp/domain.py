from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import Enum


ACTIVE = "active"
CANCELLED = "cancelled"
EXPIRED = "expired"

ROLE_PARENT = "parent"
ROLE_CHILD = "child"
ROLES = {ROLE_PARENT, ROLE_CHILD}

LOGIN_MIN_LENGTH = 3
LOGIN_MAX_LENGTH = 32
LOGIN_ALLOWED_CHARS = set("abcdefghijklmnopqrstuvwxyz0123456789._-")
PASSWORD_MIN_LENGTH = 6


class DomainError(ValueError):
    pass


class DurationUnit(str, Enum):
    DAYS = "days"
    WEEKS = "weeks"
    MONTHS = "months"


class AuthError(Exception):
    """Raised when a request is not authenticated."""


class PermissionDenied(Exception):
    """Raised when an authenticated member is not allowed to do something."""


@dataclass(frozen=True)
class Member:
    """A participant in one family, optionally linked to an independent user."""

    id: int
    name: str
    role: str
    icon: str = "star"
    login: str | None = None

    @property
    def is_parent(self) -> bool:
        return self.role == ROLE_PARENT


@dataclass(frozen=True)
class Restriction:
    id: int
    child_id: int
    start_date: date
    end_date: date
    reason: str
    status: str
    restriction_type_id: int | None = None
    custom_type_name: str | None = None
    color: str | None = None


@dataclass(frozen=True)
class RestrictionType:
    id: int
    name: str
    color: str
    archived: bool


def parse_date(value: str, field_name: str) -> date:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise DomainError(f"{field_name} must be an ISO date") from exc


def validate_restriction_dates(start_date: date, end_date: date) -> None:
    if end_date < start_date:
        raise DomainError("end_date must be on or after start_date")


def parse_positive_int(value: object, field_name: str) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise DomainError(f"{field_name} must be a positive integer") from exc
    if parsed < 1:
        raise DomainError(f"{field_name} must be a positive integer")
    return parsed


def compute_end_date(start_date: date, duration_count: int, duration_unit: str) -> date:
    if duration_unit == DurationUnit.DAYS.value:
        return start_date.replace() + date.resolution * (duration_count - 1)
    if duration_unit == DurationUnit.WEEKS.value:
        return start_date.replace() + date.resolution * (duration_count * 7 - 1)
    if duration_unit == DurationUnit.MONTHS.value:
        return add_months(start_date, duration_count) - date.resolution
    raise DomainError("duration_unit must be days, weeks, or months")


def add_months(value: date, months: int) -> date:
    month_index = value.month - 1 + months
    year = value.year + month_index // 12
    month = month_index % 12 + 1
    day = min(value.day, days_in_month(year, month))
    return date(year, month, day)


def days_in_month(year: int, month: int) -> int:
    if month == 12:
        next_month = date(year + 1, 1, 1)
    else:
        next_month = date(year, month + 1, 1)
    return (next_month - date(year, month, 1)).days


def validate_hex_color(value: str, field_name: str = "color") -> str:
    cleaned = (value or "").strip()
    if len(cleaned) != 7 or cleaned[0] != "#":
        raise DomainError(f"{field_name} must be a #RRGGBB color")
    try:
        int(cleaned[1:], 16)
    except ValueError as exc:
        raise DomainError(f"{field_name} must be a #RRGGBB color") from exc
    return cleaned.upper()


def validate_role(value: str) -> str:
    cleaned = (value or "").strip()
    if cleaned not in ROLES:
        raise DomainError("role must be parent or child")
    return cleaned


def normalize_login(value: str) -> str:
    cleaned = (value or "").strip().lower()
    if not LOGIN_MIN_LENGTH <= len(cleaned) <= LOGIN_MAX_LENGTH:
        raise DomainError(
            f"login must be {LOGIN_MIN_LENGTH}-{LOGIN_MAX_LENGTH} characters long"
        )
    if not set(cleaned) <= LOGIN_ALLOWED_CHARS:
        raise DomainError("login may contain only latin letters, digits, '.', '_' and '-'")
    return cleaned


def validate_password(value: str) -> str:
    if not isinstance(value, str) or len(value) < PASSWORD_MIN_LENGTH:
        raise DomainError(f"password must be at least {PASSWORD_MIN_LENGTH} characters long")
    return value


def effective_status(stored_status: str, end_date: date, today: date | None = None) -> str:
    if stored_status == CANCELLED:
        return CANCELLED

    today = today or date.today()
    if end_date < today:
        return EXPIRED

    return ACTIVE


def ensure_active(stored_status: str, end_date: date, today: date | None = None) -> None:
    if effective_status(stored_status, end_date, today) != ACTIVE:
        raise DomainError("restriction is not active")
