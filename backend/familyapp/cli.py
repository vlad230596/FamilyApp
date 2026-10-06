"""Operator commands; passwords are entered interactively, never as arguments."""
import click
from werkzeug.security import generate_password_hash

from .domain import DomainError, validate_password
from .persistence import get_db, now_iso


def bootstrap_parents(vlad_password: str, katya_password: str) -> int:
    """Atomically create two new parent accounts in one new family."""
    validate_password(vlad_password)
    validate_password(katya_password)
    db = get_db()
    timestamp = now_iso()
    with db:
        db.execute("BEGIN IMMEDIATE")
        if db.execute("SELECT 1 FROM users WHERE login IN ('vlad', 'katya')").fetchone():
            raise DomainError("vlad or katya already exists; no accounts were changed")
        family = db.execute("INSERT INTO families(name, created_at) VALUES (?, ?)", ("Семья", timestamp))
        family_id = int(family.lastrowid)
        for name, login, password in (("Влад", "vlad", vlad_password), ("Катя", "katya", katya_password)):
            user = db.execute(
                "INSERT INTO users(name, login, password_hash, created_at) VALUES (?, ?, ?, ?)",
                (name, login, generate_password_hash(password), timestamp),
            )
            db.execute(
                "INSERT INTO members(name, role, icon, family_id, user_id, created_at, updated_at) VALUES (?, 'parent', 'star', ?, ?, ?, ?)",
                (name, family_id, user.lastrowid, timestamp, timestamp),
            )
    return family_id


def register_commands(app):
    @app.cli.command("bootstrap-parents")
    def bootstrap_parents_command():
        """Create Vlad and Katya as equal parents with hidden password prompts."""
        if get_db().execute("SELECT 1 FROM users WHERE login IN ('vlad', 'katya')").fetchone():
            raise click.ClickException("vlad or katya already exists; no accounts were changed")
        passwords = []
        for name in ("Влад", "Катя"):
            password = click.prompt(f"Пароль для {name} (минимум 12 символов)", hide_input=True, confirmation_prompt=True)
            if len(password) < 12:
                raise click.ClickException("Используйте пароль минимум из 12 символов")
            passwords.append(password)
        try:
            bootstrap_parents(*passwords)
        except DomainError as exc:
            raise click.ClickException(str(exc)) from exc
        click.echo("Созданы Влад (vlad) и Катя (katya), оба — родители одной семьи.")
