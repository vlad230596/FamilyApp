# Alice integration

The Alice integration reads restrictions and, with separate permissions, reads
and adds shopping items. It never creates, extends or cancels restrictions.
The Flask backend hosts both the skill webhook and a confidential
OAuth 2.0 authorization-code client. No Yandex Cloud function is required.

## VDS preparation status (2026-10-07)

The server was accessed with the existing FamilyApp administration SSH key,
using its already trusted IP host entry. At preparation time production was on release `0.2.0`;
both FamilyApp containers are healthy and `/health` returns `{"status":"ok"}`.
No release, image replacement, container recreation or Caddy reload was performed during preparation. Deployment was completed on 2026-10-08; see Verification below.

Created `/opt/familyapp/.alice.env`, owned by root with mode 0600, with client ID
`familyapp-alice` and independently generated OAuth and cookie-signing secrets.
The skill ID was initially empty. It is now configured as `068d075d-322a-4973-bf62-da2ddadee964`.
The client secret alone was downloaded into the ignored local file
`.tmp/alice-yandex-client-secret.txt`, with access restricted to the current
Windows user. Its contents must only be pasted into the Yandex account-linking
secret field; the cookie-signing secret stays on the server.

Prepared `/opt/familyapp/setup/alice/compose.prod.yaml` and
`/opt/familyapp/setup/alice/Caddyfile.candidate`, plus timestamped originals and
an operator note. Compose `config -q` and Caddy `validate` succeeded. Docker
Compose on the server is 5.0.2. These files were initially staged. The Compose
configuration is now active; Caddy was updated against its latest shared
configuration, preserving the other projects.

The owner can create the Yandex skill and fill the fields below now. Live
account linking can now be tested against the deployed adapter. The Yandex console's
acceptance of port 8443 is still unverified.

## Owner console checklist

1. Open [Yandex Dialogs](https://dialogs.yandex.ru/developer/) using the Yandex
   account on the speaker. Create a dialog and select an Alice skill, or edit
   the previously created skill.
2. Choose a distinctive name, set access to Private, select the HTTPS webhook
   backend from the table below, and leave screen-required disabled.
3. On the account-linking tab, use client ID `familyapp-alice`, paste the local
   client-secret file's contents, and set all URLs and scope from the table.
   No separate Yandex ID OAuth application registration is needed: FamilyApp
   is the OAuth authorization server for this integration.
4. Fill the mandatory publication fields, including an icon, description,
   category, developer details and activation examples. Suggested description:
   "Помогает семье узнавать действующие ограничения детей и дату их окончания.
   Требуется подключение учётной записи FamilyApp. Изменение ограничений
   доступно только в приложении."
5. Save the draft and send the skill ID from General information to the server
   operator, who sets `FAMILYAPP_ALICE_SKILL_ID` before deployment.
6. After server deployment, first check the Testing tab, link a parent account
   and choose a family. Use the documented restriction questions. Then publish
   privately and check activation and account linking on the actual speaker.

References: [creating a skill](https://yandex.ru/dev/dialogs/alice/doc/ru/skill-create-console),
[publication settings](https://yandex.ru/dev/dialogs/alice/doc/ru/publish-settings),
[account-linking fields](https://yandex.ru/dev/dialogs/alice/doc/ru/auth/add-skill-to-console).

## Endpoints and Yandex console settings

Production origin: `https://famly-app.duckdns.org:8443`.

| Console field | Value |
| --- | --- |
| Skill type | General/dialog skill |
| Access | Private during initial testing |
| Backend / Webhook URL | `https://famly-app.duckdns.org:8443/integrations/alice/webhook` |
| OAuth application identifier | Value of `FAMILYAPP_ALICE_CLIENT_ID` |
| OAuth application secret | Value of `FAMILYAPP_ALICE_CLIENT_SECRET` |
| Authorization URL | `https://famly-app.duckdns.org:8443/integrations/alice/authorize` |
| Token URL | `https://famly-app.duckdns.org:8443/integrations/alice/token` |
| Refresh token URL | Same `/integrations/alice/token` URL |
| Action group identifier / scope | `restrictions:read&shopping:read&shopping:write` (shopping-enabled backend required) |
| Device with a screen required | No |

The only allowed OAuth redirect is exactly
`https://social.yandex.net/broker/redirect`. Both HTTP Basic client authentication
and form `client_id`/`client_secret` are supported. Token requests use
`application/x-www-form-urlencoded`, with standard `authorization_code` or
`refresh_token` grants. A code exchange must include the same `redirect_uri`.

The server recognizes the documented phrases itself, so configuring Yandex
intents is optional for this version. Activation is still handled by Yandex:
choose and test a distinctive activation name, for example "Семейный помощник"
(availability and approval are not guaranteed). Start the skill before asking
the questions below. The console always treats the skill as active, so activation
must also be tested on the real speaker.

## Server configuration and deployment

The integration returns HTTP 503 until all three settings are provided:

- `FAMILYAPP_ALICE_CLIENT_ID`: a chosen client identifier, e.g. `familyapp-alice`.
- `FAMILYAPP_ALICE_CLIENT_SECRET`: a random secret shared only with the Yandex console.
- `FAMILYAPP_ALICE_COOKIE_SECRET`: a separate random signing secret, never shared with Yandex.

Additionally set `FAMILYAPP_ALICE_SKILL_ID` after creating the skill to reject
requests for other skills. This check supplements token authentication; a skill
identifier alone never authorizes access. `FAMILYAPP_ALICE_TIMEZONE` defaults to
`Europe/Moscow` and is the fallback for missing/invalid device timezones.

Generate each secret independently with `python -c "import secrets;
print(secrets.token_urlsafe(48))"` in your own terminal. Do not paste secrets into
repository files, issues, chat, or command arguments. Keep both secrets stable
across backend restarts and use different values for development and production.

For Docker, create `/opt/familyapp/.alice.env` on the VDS, owned by root with mode
0600, containing these environment variables. The Compose file loads it as an
optional `env_file`; a missing file keeps Alice disabled and does not break
ordinary app deployment. This needs [Docker Compose 2.24.0 or newer](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/) for
`required: false`. The release script replaces `.release.env`, so do not place
Alice configuration there. Updating `.alice.env` requires recreating the backend
container; a simple restart does not reload it.

Install the updated `compose.prod.yaml` on the server alongside the usual
release. The SQLite tables are added automatically without changing existing
account, restriction or chore records. The updated Caddy snippet routes
`/integrations/alice/*` to the backend. Review and apply this change to the shared
ingress before testing; otherwise the requests reach Flutter. No changes to the
VPN or host port 443 are needed in the repository configuration.

Verify that the Yandex console accepts the HTTPS origin with port 8443 and that
it can reach the webhook. Live HTTPS access on the VDS is verified; access from
the Yandex console remains to be tested. Use a publicly valid fullchain certificate. If Yandex rejects
the port, decide on ingress changes separately before changing the shared VDS.

Flask does not automatically load the supplied `backend/.env.example`; export
environment variables in the launching process for local development. Consent
cookies require HTTPS by default. HTTP preview explicitly overrides
`ALICE_COOKIE_SECURE=False` in a local `create_app` configuration, never in
production. Production does not require Flask's global `SECRET_KEY`: the Alice
flow uses the separate signing key.

## Family authorization and revocation

1. Start the skill while signed in to the Yandex account used on the speaker.
2. An unlinked request on a surface with `account_linking` returns
   `start_account_linking` alone, with no `response` field.
3. In the Yandex authorization flow, a parent signs in with their FamilyApp
   credentials, chooses a family, and explicitly grants read access.
4. Every speaker listener can query restrictions of that family. The integration
   identifies the linked account, not the individual speaking.
5. The selected family stays fixed even when the parent switches families in
   the Flutter app.

To revoke a connection, open
`https://famly-app.duckdns.org:8443/integrations/alice/manage`, sign in as the
parent who created it, and press "Отключить доступ". Changing that parent's
password, losing parent membership, or deleting their account also invalidates
access and token refresh. App logout affects the app session only; use the
management page to revoke Alice. Creating a new linking does not implicitly
revoke older connections.

Authorization codes last 5 minutes and can be consumed only once. Access tokens
last one hour. Refresh tokens rotate and have an absolute 90-day lifetime from
the original code exchange; then the parent reconnects. Previous access tokens
remain usable until their one-hour expiry to tolerate in-flight requests during
refresh. Revoking a grant invalidates all its access and refresh tokens at once.
Only token/code hashes are stored in SQLite. App tokens cannot authenticate the
Alice webhook, and Alice tokens cannot authenticate the regular app API.

Login is protected by signed 10-minute HttpOnly, SameSite=Lax cookies, CSRF
tokens, and persistent per-address/per-login limits (10 attempts per minute).
Token requests are limited to 120 per minute per address. Reverse proxies may
cause several users to share the address limit; untrusted `X-Forwarded-For` is
deliberately not used. Authorization/token responses are not cached and have no
CORS access. Avoid enabling request-body, Authorization-header, or OAuth
callback-query logging on the VDS or in observability tools.

## Supported conversations

- "Какие сегодня ограничения у ребят?"
- "Что детям сегодня нельзя?"
- "Какие ограничения у Миши?"
- "Что сегодня нельзя Михаилу?"
- "Можно Мише сегодня мультики посмотреть?"
- "Миша сегодня может смотреть мультфильмы?"
- "Когда Мише снова можно мультики?"
- "До какого дня Мише нельзя смотреть мультфильмы?"
- Follow-ups: "А завтра?", "А у Маши?", "Повтори".
- "Помощь", "Что ты умеешь?", "Выход".

The adapter supports today, tomorrow, the day after tomorrow, yesterday, and
an explicit `YYYY-MM-DD` date. Other date phrases ask for clarification.
The current date uses `meta.timezone` (IANA), falling back to the configured
timezone. Restrictions have inclusive end dates. For permission questions the
backend merges overlapping/adjacent intervals of the requested activity before
announcing the next unrestricted date. Cancelled restrictions never count;
historical queries use the stored status and queried dates rather than the
server's current effective status.

Common Russian name variants are supported, including Михаил/Миша,
Мария/Маша, Анна/Аня and Александр/Саша. Matching is limited to children of the
linked family. Ambiguous forms (e.g. Саша for two children) ask for clarification.
Name dictionaries are intentionally finite: uncommon nicknames may require the
name recorded in the app, and custom nicknames are not configurable yet.

Activity synonyms cover cartoons, phones, tablets, games, TV and computers.
They match the corresponding words in restriction type names. Other type names
can be requested by their normalized exact label, including one-off types found
in the family's restriction history. For a custom type with an unrelated name,
use that name; the backend cannot infer that, for example, "Видео" means
"Мультфильмы". Arbitrary semantic paraphrases, weekday dates and interpreting
the free-text reason as a rule are not supported.

An absent restriction is phrased as "В FamilyApp ... нет ограничения", not as a
new parental permission. Queries never read the reason or audit history aloud.
Long summaries stop before 1800 characters and direct the listener to the app
for the rest. Follow-up context is signed, bound to the OAuth grant, expires
after 30 minutes, and is returned via `session_state`. Forged context is ignored.
After account linking the skill reads today's summary; it does not restore the
exact pre-linking question in this version.

## Verification

### Shopping voice extension (release 0.4.0)

The shared family shopping list can be read and one item can be added per
command. Supported examples: "Что нужно купить?", "Прочитай список покупок",
"Добавь в список покупок молоко", and "Запиши хлеб в список покупок".
An add command without a name asks for one item and accepts the next reply.
Completed reads and additions return `end_session: true`. Empty lists have a
short explicit response; long lists are bounded and refer to the app.

The extension uses the existing shopping domain. Voice additions use default
urgency and category and do not escalate urgency on duplicates. Audit member
IDs refer to the parent who linked the family, not the unidentified speaker.
Purchases, removal, urgency filtering and category filtering are not supported.

After deploying this extension, set the console action group identifier to
`restrictions:read&shopping:read&shopping:write`, save/publish the updated skill,
and reconnect the parent account. Each permission is checked separately.
Existing grants are migrated with `restrictions:read` only; refreshing a token
cannot upgrade permissions. The consent page explicitly describes reading and
adding shopping items for everyone who can speak to the device.

### Production deployment, 2026-10-08

Release `0.3.0` is deployed. The Alice environment file is loaded by the backend,
and Caddy routes `/integrations/alice/*` to it. The configured skill ID is
`068d075d-322a-4973-bf62-da2ddadee964`.

Live HTTPS checks passed for health, the account management and authorization
pages, an unlinked webhook requesting account linking, and rejection of a wrong
skill ID. Backend and web containers report version `0.3.0` and are healthy.
No private family data was accessed. Real Yandex account linking and speaker
verification remain to be performed by the project owner.

Run from `backend/`: `poetry run pytest`.

Tests cover OAuth consent, exact redirect validation, client authentication,
CSRF, login limits, one-use codes, refresh rotation, expiry, revocation,
password changes, parent-only linking, family isolation, family switching,
read-only behavior, inclusive/contiguous periods, cancellation, aliases,
unknown names, clarification, follow-ups, invalid context, and bounded replies.

For the console/speaker test, prepare real restrictions in the app, then check:

1. First launch and account linking, including a speaker without a screen.
2. Today's summary, no restrictions, and a restriction whose last day is today.
3. A child name, a permission question, and "А завтра?".
4. A changed/cancelled restriction is reflected immediately without redeployment.
5. Unknown/ambiguous names, unsupported phrases, and an attempted cancellation.
6. Revocation and subsequent request for re-linking.
7. Activation-name recognition and end-to-end response time under 4.5 seconds.

Official references, checked 2026-10-07:

- [Request format](https://yandex.ru/dev/dialogs/alice/doc/ru/request)
- [Response format and timeout](https://yandex.ru/dev/dialogs/alice/doc/ru/response)
- [Authorization server](https://yandex.ru/dev/dialogs/alice/doc/ru/auth/create-server)
- [Authorization responses/events](https://yandex.ru/dev/dialogs/alice/doc/ru/auth/make-skill)
- [Account-linking console settings](https://yandex.ru/dev/dialogs/alice/doc/ru/auth/add-skill-to-console)
- [Testing](https://yandex.ru/dev/dialogs/alice/doc/ru/test)
