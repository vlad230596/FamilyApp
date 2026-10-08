from __future__ import annotations

from functools import wraps

from flask import Blueprint, g, jsonify, request

from .accounts import (
    authenticate,
    create_member,
    get_member,
    list_members,
    login,
    revoke_session,
    set_credentials,
    register, account_state, create_family, select_family,
    create_invitation, accept_invitation,
    update_member,
)
from .domain import (
    ROLE_CHILD,
    AuthError,
    DomainError,
    Member,
    PermissionDenied,
    compute_end_date,
    parse_date,
    parse_positive_int,
    validate_restriction_dates,
)
from .persistence import (
    archive_restriction_type,
    cancel_restriction,
    create_restriction,
    create_restriction_type,
    extend_restriction,
    get_child,
    list_children,
    list_restriction_types,
    list_restrictions,
    list_restrictions_for_range,
    list_today_restrictions,
)
from .chores import list_chores, save_chore, answer_chore, answer_history, reminders

from . import shopping

api = Blueprint("api", __name__)

PUBLIC_ENDPOINTS = {"api.health", "api.auth_register", "api.auth_login"}


@api.errorhandler(DomainError)
def handle_domain_error(error: DomainError):
    return jsonify({"error": str(error)}), 400


@api.errorhandler(AuthError)
def handle_auth_error(error: AuthError):
    return jsonify({"error": str(error)}), 401


@api.errorhandler(PermissionDenied)
def handle_permission_denied(error: PermissionDenied):
    return jsonify({"error": str(error) or "parent access required"}), 403


@api.before_request
def require_authentication():
    if request.method == "OPTIONS" or request.endpoint in PUBLIC_ENDPOINTS:
        return None
    header = request.headers.get("Authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise AuthError("authentication required")
    g.member, g.session_id = authenticate(token.strip())
    if request.endpoint not in {"api.me", "api.auth_logout", "api.families_create", "api.families_select", "api.invitations_accept"} and g.member is None:
        raise PermissionDenied("family selection required")
    return None


def current_member() -> Member:
    return g.member


def parent_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not current_member().is_parent:
            raise PermissionDenied("parent access required")
        return view(*args, **kwargs)

    return wrapper


def visible_child_id(requested: int | None = None) -> int | None:
    """Children only ever see their own restrictions."""
    member = current_member()
    if member.role == ROLE_CHILD:
        return member.id
    return requested


def request_payload() -> dict:
    if request.is_json:
        return request.get_json(silent=True) or {}
    return request.form.to_dict()


@api.get("/api/chores")
def chores_list():
    return jsonify(chores=list_chores())


@api.post("/api/chores")
@parent_required
def chores_create():
    return jsonify(chore=save_chore(request_payload())), 201


@api.post("/api/chores/<int:chore_id>")
@parent_required
def chores_update(chore_id):
    return jsonify(chore=save_chore(request_payload(), chore_id))


@api.post("/api/chores/<int:chore_id>/answers")
def chores_answer(chore_id):
    return jsonify(chore=answer_chore(chore_id, request_payload()))


@api.get("/api/chores/<int:chore_id>/answers")
def chores_history(chore_id):
    return jsonify(answers=answer_history(chore_id))


@api.get("/api/chores/reminders")
def chores_reminders():
    return jsonify(reminders=reminders())


@api.get("/api/shopping")
def shopping_list():
    return jsonify(shopping.list_shopping())


@api.post("/api/shopping")
def shopping_add():
    return jsonify(item=shopping.save_item(request_payload())), 201


@api.post("/api/shopping/<int:item_id>/buy")
def shopping_buy(item_id):
    shopping.buy_item(item_id, request_payload())
    return jsonify(ok=True)


@api.post("/api/shopping/purchases/<int:purchase_id>/return")
def shopping_return(purchase_id):
    shopping.return_purchase(purchase_id)
    return jsonify(ok=True)


@api.post("/api/shopping/purchases/<int:purchase_id>/cancel-return")
def shopping_cancel_return(purchase_id):
    shopping.return_purchase(purchase_id, cancel=True)
    return jsonify(ok=True)


@api.get("/health")
def health():
    return jsonify({"status": "ok"})


@api.post("/api/auth/register")
def auth_register():
    payload = request_payload()
    token, user_id = register(payload.get("name", ""), payload.get("login", ""), payload.get("password", ""))
    return jsonify({"token": token, **account_state(user_id)}), 201


@api.post("/api/auth/login")
def auth_login():
    payload = request_payload()
    token, user_id = login(payload.get("login", ""), payload.get("password", ""))
    member, session_id = authenticate(token)
    g.member, g.session_id = member, session_id
    return jsonify({"token": token, **account_state(user_id)})


@api.post("/api/families")
def families_create():
    return jsonify(create_family(request_payload().get("name", ""))), 201


@api.post("/api/families/<int:selected>/select")
def families_select(selected):
    return jsonify(select_family(selected))


@api.post("/api/invitations")
@parent_required
def invitations_create():
    payload = request_payload()
    return jsonify(create_invitation(payload.get("role", "parent"), payload.get("member_id"))), 201


@api.post("/api/invitations/accept")
def invitations_accept():
    return jsonify(accept_invitation(request_payload().get("code", "")))


@api.post("/api/auth/logout")
def auth_logout():
    revoke_session(g.session_id)
    return jsonify({"status": "ok"})


@api.get("/api/me")
def me():
    return jsonify(account_state(g.user_id))


@api.get("/api/members")
def members_index():
    return jsonify({"members": list_members()})


@api.post("/api/members")
@parent_required
def members_create():
    payload = request_payload()
    member = create_member(
        name=payload.get("name", ""),
        icon=payload.get("icon", "star"),
        role=payload.get("role", ""),
        actor_id=current_member().id,
        login=payload.get("login"),
        password=payload.get("password"),
    )
    return jsonify({"member": member}), 201


@api.route("/api/members/<int:member_id>", methods=["POST", "PUT"])
@parent_required
def members_update(member_id: int):
    payload = request_payload()
    member = update_member(
        member_id,
        name=payload.get("name", ""),
        icon=payload.get("icon", "star"),
    )
    return jsonify({"member": member})


@api.post("/api/members/<int:member_id>/credentials")
def members_credentials(member_id: int):
    actor = current_member()
    if not actor.is_parent and actor.id != member_id:
        raise PermissionDenied("parent access required")
    payload = request_payload()
    member = set_credentials(
        member_id,
        login=payload.get("login", ""),
        password=payload.get("password", ""),
        keep_session_id=g.session_id if actor.id == member_id else None,
    )
    return jsonify({"member": member})


@api.get("/api/children")
def children_index():
    return jsonify({"children": list_children()})


@api.post("/api/children")
@parent_required
def children_create():
    payload = request_payload()
    member = create_member(
        name=payload.get("name", ""),
        icon=payload.get("icon", "star"),
        role=ROLE_CHILD,
        actor_id=current_member().id,
    )
    return jsonify({"child": get_child(member["id"])}), 201


@api.post("/api/children/<int:child_id>/update")
@parent_required
def children_update_explicit(child_id: int):
    return update_child_response(child_id)


@api.route("/api/children/<int:child_id>", methods=["POST", "PUT"])
@parent_required
def children_update(child_id: int):
    return update_child_response(child_id)


def update_child_response(child_id: int):
    get_child(child_id)
    payload = request_payload()
    update_member(
        child_id,
        name=payload.get("name", ""),
        icon=payload.get("icon", "star"),
    )
    return jsonify({"child": get_child(child_id)})


@api.get("/api/restrictions")
def restrictions_index():
    raw_child_id = request.args.get("child_id")
    child_id = visible_child_id(int(raw_child_id) if raw_child_id else None)
    return jsonify({"restrictions": list_restrictions(child_id)})


@api.get("/api/restriction-types")
def restriction_types_index():
    include_archived = request.args.get("include_archived") == "true"
    return jsonify(
        {"restriction_types": list_restriction_types(include_archived=include_archived)}
    )


@api.post("/api/restriction-types")
@parent_required
def restriction_types_create():
    payload = request.get_json(silent=True) or {}
    restriction_type = create_restriction_type(
        name=payload.get("name", ""),
        color=payload.get("color", ""),
    )
    return jsonify({"restriction_type": restriction_type}), 201


@api.post("/api/restriction-types/<int:restriction_type_id>/archive")
@parent_required
def restriction_types_archive(restriction_type_id: int):
    restriction_type = archive_restriction_type(restriction_type_id)
    return jsonify({"restriction_type": restriction_type})


@api.post("/api/restrictions")
@parent_required
def restrictions_create():
    payload = request.get_json(silent=True) or {}
    start_date = parse_date(payload.get("start_date"), "start_date")
    if payload.get("duration_count") is not None or payload.get("duration_unit") is not None:
        duration_count = parse_positive_int(payload.get("duration_count"), "duration_count")
        end_date = compute_end_date(
            start_date,
            duration_count,
            payload.get("duration_unit", ""),
        )
    else:
        end_date = parse_date(payload.get("end_date"), "end_date")
    validate_restriction_dates(start_date, end_date)
    raw_type_id = payload.get("restriction_type_id")
    restriction = create_restriction(
        child_id=int(payload.get("child_id")),
        start_date=start_date,
        end_date=end_date,
        reason=payload.get("reason", ""),
        restriction_type_id=int(raw_type_id) if raw_type_id is not None else None,
        custom_type_name=payload.get("custom_type_name"),
        color=payload.get("color"),
        admin_id=current_member().id,
    )
    return jsonify({"restriction": restriction}), 201


@api.get("/api/restrictions/today")
def restrictions_today():
    raw_today = request.args.get("date")
    today = parse_date(raw_today, "date") if raw_today else None
    return jsonify({"restrictions": list_today_restrictions(today, visible_child_id())})


@api.get("/api/restrictions/range")
def restrictions_range():
    start_date = parse_date(request.args.get("start_date"), "start_date")
    end_date = parse_date(request.args.get("end_date"), "end_date")
    validate_restriction_dates(start_date, end_date)
    return jsonify(
        {
            "restrictions": list_restrictions_for_range(
                start_date,
                end_date,
                visible_child_id(),
            )
        }
    )


@api.post("/api/restrictions/<int:restriction_id>/extend")
@parent_required
def restrictions_extend(restriction_id: int):
    payload = request.get_json(silent=True) or {}
    new_end_date = parse_date(payload.get("new_end_date"), "new_end_date")
    restriction = extend_restriction(
        restriction_id,
        new_end_date,
        admin_id=current_member().id,
        note=payload.get("note"),
    )
    return jsonify({"restriction": restriction})


@api.post("/api/restrictions/<int:restriction_id>/cancel")
@parent_required
def restrictions_cancel(restriction_id: int):
    payload = request.get_json(silent=True) or {}
    restriction = cancel_restriction(
        restriction_id,
        admin_id=current_member().id,
        note=payload.get("note"),
    )
    return jsonify({"restriction": restriction})
