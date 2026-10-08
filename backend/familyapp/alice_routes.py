"""Alice HTTP adapter and short-lived browser consent flow."""
from __future__ import annotations

import secrets
from urllib.parse import urlencode

from flask import Blueprint, abort, current_app, jsonify, make_response, redirect, render_template, request
from itsdangerous import BadSignature, URLSafeTimedSerializer

from . import alice_oauth as oauth
from .alice_voice import answer, spoken_response

alice = Blueprint("alice", __name__, url_prefix="/integrations/alice")
COOKIE = "familyapp_alice_flow"


def same(left, right):
    return secrets.compare_digest(left.encode("utf-8"), right.encode("utf-8"))


@alice.before_request
def require_configuration():
    request.max_content_length = 32768
    if not oauth.configured():
        return jsonify(error="alice_not_configured"), 503
    if request.content_length and request.content_length > 32768:
        abort(413)


@alice.after_request
def private_response(response):
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https://social.yandex.net; frame-ancestors 'none'; base-uri 'none'"
    # These routes are same-origin HTML or server-to-server; do not expose them via CORS.
    response.headers.pop("Access-Control-Allow-Origin", None)
    return response


def serializer():
    return URLSafeTimedSerializer(current_app.config["ALICE_COOKIE_SECRET"], salt="alice-consent")


def read_flow(mode):
    try:
        flow = serializer().loads(request.cookies.get(COOKIE, ""), max_age=600)
    except BadSignature:
        abort(400, "Страница устарела. Откройте подключение заново.")
    if flow.get("mode") != mode or not same(flow.get("csrf", ""), request.form.get("csrf", "")):
        abort(400, "Недействительный запрос. Откройте страницу заново.")
    return flow


def page(flow, error=None, message=None, status=200):
    flow["csrf"] = secrets.token_urlsafe(24)
    authenticated = oauth.valid_browser_user(flow)
    response = make_response(render_template(
        "alice_account.html", flow=flow, error=error, message=message,
        families=oauth.parent_families(flow["user_id"]) if authenticated else [],
        connections=oauth.connections(flow["user_id"]) if authenticated and flow["mode"] == "manage" else [],
        authenticated=authenticated), status)
    response.set_cookie(COOKIE, serializer().dumps(flow), max_age=600, httponly=True,
                        secure=current_app.config["ALICE_COOKIE_SECURE"], samesite="Lax",
                        path="/integrations/alice")
    return response


def login_flow(flow):
    address = request.remote_addr or "unknown"
    login = request.form.get("login", "")[:128]
    if not oauth.consume_rate_limit("login-ip:" + address) or not oauth.consume_rate_limit("login-account:" + login.strip().lower()):
        return page(flow, error="Слишком много попыток. Подождите минуту.", status=429)
    user = oauth.login_parent(login, request.form.get("password", "")[:1024])
    if not user:
        return page(flow, error="Проверьте логин и пароль. Подключение доступно только родителям.", status=401)
    flow.update(user)
    return page(flow)


@alice.route("/authorize", methods=["GET", "POST"])
def authorize():
    if request.method == "GET":
        args = request.args
        # Never redirect to an unverified URI, even on an error.
        if args.get("client_id") != current_app.config["ALICE_CLIENT_ID"] or args.get("redirect_uri") != current_app.config["ALICE_REDIRECT_URI"]:
            return jsonify(error="invalid_request"), 400
        if args.get("response_type") != "code":
            return jsonify(error="unsupported_response_type"), 400
        scope = oauth.parse_scope(args.get("scope", oauth.SCOPE))
        if scope is None:
            return jsonify(error="invalid_scope"), 400
        if len(args.get("state", "")) > 1024:
            return jsonify(error="invalid_request"), 400
        flow = {"mode": "authorize", "client_id": args["client_id"],
                "redirect_uri": args["redirect_uri"], "state": args.get("state", ""), "scope": scope}
        return page(flow)
    flow = read_flow("authorize")
    if request.form.get("action") == "deny":
        response = redirect(flow["redirect_uri"] + "?" + urlencode({"error": "access_denied", "state": flow["state"]}))
        response.delete_cookie(COOKIE, path="/integrations/alice")
        return response
    if not oauth.valid_browser_user(flow):
        return login_flow(flow)
    try:
        family_id = int(request.form.get("family_id", ""))
    except ValueError:
        return page(flow, error="Выберите семью.", status=400)
    code = oauth.issue_code(flow, family_id)
    if not code:
        return page(flow, error="Нет доступа к выбранной семье.", status=403)
    response = redirect(flow["redirect_uri"] + "?" + urlencode({"code": code, "state": flow["state"]}))
    response.delete_cookie(COOKIE, path="/integrations/alice")
    return response


@alice.route("/manage", methods=["GET", "POST"])
def manage():
    if request.method == "GET":
        return page({"mode": "manage"})
    flow = read_flow("manage")
    if not oauth.valid_browser_user(flow):
        return login_flow(flow)
    try:
        grant_id = int(request.form.get("grant_id", ""))
    except ValueError:
        abort(400)
    oauth.revoke_connection(flow["user_id"], grant_id)
    return page(flow, message="Доступ отключён. Алиса больше не сможет читать данные этой привязки.")


@alice.post("/token")
def token():
    payload = request.form.to_dict()
    auth = request.authorization
    if auth and auth.type.lower() == "basic":
        client_id, secret = auth.username or "", auth.password or ""
    else:
        client_id, secret = payload.get("client_id", ""), payload.get("client_secret", "")
    if not oauth.consume_rate_limit("token:" + (request.remote_addr or "unknown"), limit=120):
        return jsonify(error="temporarily_unavailable"), 429
    if not same(client_id, current_app.config["ALICE_CLIENT_ID"]) or not same(secret, current_app.config["ALICE_CLIENT_SECRET"]):
        response = jsonify(error="invalid_client")
        response.headers["WWW-Authenticate"] = 'Basic realm="FamilyApp Alice"'
        return response, 401
    if payload.get("grant_type") not in {"authorization_code", "refresh_token"}:
        return jsonify(error="unsupported_grant_type"), 400
    if "scope" in payload and oauth.parse_scope(payload["scope"]) is None:
        return jsonify(error="invalid_scope"), 400
    result = oauth.exchange_token(payload)
    return (jsonify(result), 200) if result else (jsonify(error="invalid_grant"), 400)


@alice.post("/webhook")
def webhook():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict) or payload.get("version") != "1.0":
        return jsonify(error="invalid_request"), 400
    session = payload.get("session")
    meta = payload.get("meta", {})
    if not isinstance(session, dict) or not isinstance(meta, dict):
        return jsonify(error="invalid_request"), 400
    expected_skill = current_app.config.get("ALICE_SKILL_ID")
    if expected_skill and session.get("skill_id") != expected_skill:
        return jsonify(error="invalid_skill"), 403
    user = session.get("user", {})
    if not isinstance(user, dict):
        return jsonify(error="invalid_request"), 400
    header = request.headers.get("Authorization", "")
    scheme, _, header_token = header.partition(" ")
    body_token = user.get("access_token", "")
    if not isinstance(body_token, str):
        return jsonify(error="invalid_request"), 400
    access = header_token if scheme.lower() == "bearer" else body_token
    if header_token and body_token and header_token != body_token:
        access = ""
    if not oauth.authenticate_alice(access):
        interfaces = meta.get("interfaces", {})
        if isinstance(interfaces, dict) and "account_linking" in interfaces:
            return jsonify(start_account_linking={}, version="1.0")
        return jsonify(spoken_response("Сначала родителю нужно связать аккаунт FamilyApp с навыком в приложении Яндекса.", end=True))
    return jsonify(answer(payload))
