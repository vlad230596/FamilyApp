from __future__ import annotations

from dataclasses import dataclass
from datetime import date


ACTIVE = "active"
CANCELLED = "cancelled"
EXPIRED = "expired"


class DomainError(ValueError):
    pass


@dataclass(frozen=True)
class ParentAdmin:
    id: int
    name: str


@dataclass(frozen=True)
class Child:
    id: int
    name: str


@dataclass(frozen=True)
class Restriction:
    id: int
    child_id: int
    start_date: date
    end_date: date
    reason: str
    status: str


def parse_date(value: str, field_name: str) -> date:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise DomainError(f"{field_name} must be an ISO date") from exc


def validate_restriction_dates(start_date: date, end_date: date) -> None:
    if end_date < start_date:
        raise DomainError("end_date must be on or after start_date")


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
