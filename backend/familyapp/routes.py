from __future__ import annotations

from flask import Blueprint, jsonify, request

from .domain import DomainError, parse_date, validate_restriction_dates
from .persistence import (
    cancel_restriction,
    create_child,
    create_restriction,
    extend_restriction,
    list_children,
    list_restrictions,
)

api = Blueprint("api", __name__)


@api.errorhandler(DomainError)
def handle_domain_error(error: DomainError):
    return jsonify({"error": str(error)}), 400


@api.get("/health")
def health():
    return jsonify({"status": "ok"})


@api.get("/api/children")
def children_index():
    return jsonify({"children": list_children()})


@api.post("/api/children")
def children_create():
    payload = request.get_json(silent=True) or {}
    child = create_child(payload.get("name", ""))
    return jsonify({"child": child}), 201


@api.get("/api/restrictions")
def restrictions_index():
    raw_child_id = request.args.get("child_id")
    child_id = int(raw_child_id) if raw_child_id else None
    return jsonify({"restrictions": list_restrictions(child_id)})


@api.post("/api/restrictions")
def restrictions_create():
    payload = request.get_json(silent=True) or {}
    start_date = parse_date(payload.get("start_date"), "start_date")
    end_date = parse_date(payload.get("end_date"), "end_date")
    validate_restriction_dates(start_date, end_date)
    restriction = create_restriction(
        child_id=int(payload.get("child_id")),
        start_date=start_date,
        end_date=end_date,
        reason=payload.get("reason", ""),
    )
    return jsonify({"restriction": restriction}), 201


@api.post("/api/restrictions/<int:restriction_id>/extend")
def restrictions_extend(restriction_id: int):
    payload = request.get_json(silent=True) or {}
    new_end_date = parse_date(payload.get("new_end_date"), "new_end_date")
    restriction = extend_restriction(
        restriction_id,
        new_end_date,
        note=payload.get("note"),
    )
    return jsonify({"restriction": restriction})


@api.post("/api/restrictions/<int:restriction_id>/cancel")
def restrictions_cancel(restriction_id: int):
    payload = request.get_json(silent=True) or {}
    restriction = cancel_restriction(restriction_id, note=payload.get("note"))
    return jsonify({"restriction": restriction})
