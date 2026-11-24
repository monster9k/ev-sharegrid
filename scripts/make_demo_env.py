"""Create the local Compose .env or update selected demo passwords."""

import argparse
import json
import os
import re
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


def prompt_password(prompt: str) -> str:
    with warnings.catch_warnings():
        warnings.simplefilter("error", GetPassWarning)
        password = getpass(prompt)
    if not 1 <= len(password) <= 1024:
        raise ValueError("Each demo password must have 1 to 1024 characters.")
    return password


def update_passwords(path: Path, replacements: dict[str, str]) -> None:
    # Serialize read/modify/write so simultaneous rotations keep both changes.
    lock = path.with_name(".env.lock")
    lock.touch(exist_ok=False)
    try:
        contents = path.read_bytes().decode("utf-8")  # Preserve CRLF and any BOM.
        assignments = list(re.finditer(
            r"(?m)^(?:\ufeff)?[ \t]*(?:export[ \t]+)?AUTH_PASSWORD_HASHES_JSON[ \t]*=[ \t]*([^\r\n]*)",
            contents,
        ))
        if len(assignments) != 1:
            raise ValueError("Expected one AUTH_PASSWORD_HASHES_JSON assignment in .env.")
        assignment = assignments[0]
        value = assignment[1]
        single_quoted = value.startswith("'")
        decoder = json.JSONDecoder()
        if single_quoted:
            hashes, end = decoder.raw_decode(value, idx=1)
            if value[end:end + 1] != "'":
                raise ValueError("Missing closing quote in AUTH_PASSWORD_HASHES_JSON.")
            end += 1
        else:
            hashes, end = decoder.raw_decode(value)
            if value.startswith('"'):
                hashes = json.loads(hashes)  # Compose double-quoted JSON string.
        if value[end:].strip() and not value[end:].lstrip().startswith("#"):
            raise ValueError("Unexpected text after AUTH_PASSWORD_HASHES_JSON.")
        if not isinstance(hashes, dict) or not all(isinstance(v, str) for v in hashes.values()):
            raise ValueError("AUTH_PASSWORD_HASHES_JSON must map emails to hashes.")
        for email, encoded in replacements.items():
            keys = [key for key in hashes if key.strip().lower() == email]
            if len(keys) != 1:
                raise ValueError(f"Expected one configured entry for {email}.")
            # Outside single quotes Compose interprets $$ as one literal dollar.
            hashes[keys[0]] = encoded if single_quoted else encoded.replace("$", "$$")
        updated = json.dumps(hashes)
        if single_quoted:
            updated = "'" + updated.replace("'", r"\u0027") + "'"
        elif value.startswith('"'):
            updated = json.dumps(updated)
        start = assignment.start(1)
        write_env(path.with_name(".env.bak"), contents, force=True)
        write_env(path, contents[:start] + updated + contents[start + end:], force=True)
    finally:
        lock.unlink()


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
    parser.add_argument(
        "--set-password", nargs="+", metavar="EMAIL", type=str.lower,
        help="Enter a new password without echo for the listed demo accounts. "
             "Backs up the current .env to .env.bak.",
    )
    args = parser.parse_args(argv)
    path = ROOT / ".env"
    if args.set_password and (args.force or args.generate_passwords):
        parser.error("--set-password cannot be combined with --force or --generate-passwords.")
    if os.path.lexists(path) and not args.force and not args.set_password:
        parser.error(".env already exists. Use --force to replace it.")

    if __package__ in (None, ""):
        sys.path.insert(0, str(ROOT))
    try:
        from backend.auth import DEMO_EMAILS, hash_password
    except ModuleNotFoundError as exc:
        if exc.name != "fastapi":
            raise
        parser.error("Install backend dependencies with python -m pip install -r backend/requirements.txt.")

    if args.set_password:
        if any(email not in DEMO_EMAILS for email in args.set_password):
            parser.error("--set-password accepts these demo accounts: " + ", ".join(DEMO_EMAILS))
        if not path.is_file():
            parser.error("--set-password requires an existing .env.")
        try:
            password = prompt_password("New password for " + ", ".join(args.set_password) + ": ")
            update_passwords(path, {email: hash_password(password) for email in args.set_password})
        except (EOFError, GetPassWarning, KeyboardInterrupt):
            parser.error("Use a terminal that can hide password input.")
        except FileExistsError:
            parser.error("Another password update holds .env.lock.")
        except (ValueError, OSError) as exc:
            parser.error(str(exc))
        print("Updated the selected demo accounts. Previous configuration saved to .env.bak.")
        return

    if args.generate_passwords:
        passwords = {email: secrets.token_urlsafe(18) for email in DEMO_EMAILS}
    else:
        try:
            passwords = {email: prompt_password(f"Password for {email}: ") for email in DEMO_EMAILS}
        except (EOFError, GetPassWarning, KeyboardInterrupt):
            parser.error("Use a terminal that can hide password input, or pass --generate-passwords.")
        except ValueError as exc:
            parser.error(str(exc))

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
