"""Create a local .env for the EV ShareGrid Docker Compose demo."""

import argparse
import json
import os
import secrets
import sys
import warnings
from getpass import GetPassWarning, getpass
from pathlib import Path
from tempfile import NamedTemporaryFile


ROOT = Path(__file__).resolve().parents[1]


def write_env(path: Path, contents: str, force: bool) -> None:
    if force:
        staged_path = None
        try:
            with NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                newline="\n",
                dir=path.parent,
                prefix=".env.",
                delete=False,
            ) as staged:
                staged_path = Path(staged.name)
                staged.write(contents)
            staged_path.replace(path)
        finally:
            if staged_path is not None:
                staged_path.unlink(missing_ok=True)
        return

    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as output:
            output.write(contents)
    except OSError:
        path.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="A new PostgreSQL password applies when initializing a fresh volume. "
        "Replacing .env does not change an existing database password.",
    )
    parser.add_argument("--force", action="store_true", help="Replace the existing .env.")
    parser.add_argument(
        "--generate-passwords", action="store_true",
        help="Generate demo login passwords and print them once.",
    )
    args = parser.parse_args(argv)
    path = ROOT / ".env"
    if os.path.lexists(path) and not args.force:
        parser.error(".env already exists. Use --force to replace it.")

    if __package__ in (None, ""):
        sys.path.insert(0, str(ROOT))
    try:
        from backend.auth import DEMO_EMAILS, hash_password
    except ModuleNotFoundError as exc:
        if exc.name != "fastapi":
            raise
        parser.error("Install backend dependencies with python -m pip install -r backend/requirements.txt.")

    if args.generate_passwords:
        passwords = {email: secrets.token_urlsafe(18) for email in DEMO_EMAILS}
    else:
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", GetPassWarning)
                passwords = {email: getpass(f"Password for {email}: ") for email in DEMO_EMAILS}
        except (EOFError, GetPassWarning, KeyboardInterrupt):
            parser.error("Use a terminal that can hide password input, or pass --generate-passwords.")
        if any(not 1 <= len(password) <= 1024 for password in passwords.values()):
            parser.error("Each demo password must have 1 to 1024 characters.")

    hashes = json.dumps({email: hash_password(password) for email, password in passwords.items()})
    contents = (
        f"POSTGRES_PASSWORD={secrets.token_urlsafe(32)}\n"
        f"JWT_SECRET={secrets.token_urlsafe(48)}\n"
        f"AUTH_PASSWORD_HASHES_JSON='{hashes}'\n"
        "AI_URL=http://ai-engine:8001\n"
    )
    try:
        write_env(path, contents, args.force)
    except FileExistsError:
        parser.error(".env already exists. Use --force to replace it.")
    except OSError as exc:
        parser.error(f"Could not write .env: {exc}")

    print("Created local .env.")
    if args.generate_passwords:
        for email, password in passwords.items():
            print(f"{email}\t{password}")


if __name__ == "__main__":
    main()
