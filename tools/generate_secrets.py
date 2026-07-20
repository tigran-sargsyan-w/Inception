#!/usr/bin/env python3

import argparse
import getpass
import os
import secrets
import string
import sys
from pathlib import Path


PASSWORD_LENGTH = 32

USE_UPPERCASE = True
USE_LOWERCASE = True
USE_DIGITS = True
USE_SPECIAL_CHARACTERS = True

SPECIAL_CHARACTERS = "!@#%+=_-"

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SECRETS_DIRECTORY = PROJECT_ROOT / "secrets"

SECRET_FILES = {
    "MariaDB root": SECRETS_DIRECTORY / "db_root_password.txt",
    "MariaDB user": SECRETS_DIRECTORY / "db_password.txt",
}


COLOR_ENABLED = sys.stdout.isatty() and "NO_COLOR" not in os.environ

RESET = "\033[0m" if COLOR_ENABLED else ""
BOLD = "\033[1m" if COLOR_ENABLED else ""

GREEN = "\033[32m" if COLOR_ENABLED else ""
YELLOW = "\033[33m" if COLOR_ENABLED else ""
RED = "\033[31m" if COLOR_ENABLED else ""
CYAN = "\033[36m" if COLOR_ENABLED else ""


def print_success(message: str) -> None:
    print(f"{GREEN}✅ {message}{RESET}")


def print_info(message: str) -> None:
    print(f"{CYAN}ℹ️  {message}{RESET}")


def print_warning(message: str) -> None:
    print(f"{YELLOW}⚠️  {message}{RESET}")


def print_error(message: str) -> None:
    print(f"{RED}❌ {message}{RESET}")


def get_enabled_character_groups() -> list[str]:
    character_groups = []

    if USE_UPPERCASE:
        character_groups.append(string.ascii_uppercase)

    if USE_LOWERCASE:
        character_groups.append(string.ascii_lowercase)

    if USE_DIGITS:
        character_groups.append(string.digits)

    if USE_SPECIAL_CHARACTERS:
        character_groups.append(SPECIAL_CHARACTERS)

    return character_groups


def validate_configuration() -> None:
    character_groups = get_enabled_character_groups()

    if not character_groups:
        raise ValueError(
            "At least one character category must be enabled."
        )

    if PASSWORD_LENGTH < len(character_groups):
        raise ValueError(
            "PASSWORD_LENGTH is too small for the enabled categories."
        )


def validate_password(password: str) -> list[str]:
    errors = []

    if len(password) < PASSWORD_LENGTH:
        errors.append(
            f"password must contain at least {PASSWORD_LENGTH} characters"
        )

    if USE_UPPERCASE and not any(
        character.isupper() for character in password
    ):
        errors.append("password must contain an uppercase letter")

    if USE_LOWERCASE and not any(
        character.islower() for character in password
    ):
        errors.append("password must contain a lowercase letter")

    if USE_DIGITS and not any(
        character.isdigit() for character in password
    ):
        errors.append("password must contain a digit")

    if USE_SPECIAL_CHARACTERS and not any(
        character in SPECIAL_CHARACTERS
        for character in password
    ):
        errors.append(
            "password must contain one of these special characters: "
            f"{SPECIAL_CHARACTERS}"
        )

    return errors


def generate_password() -> str:
    character_groups = get_enabled_character_groups()
    alphabet = "".join(character_groups)

    characters = [
        secrets.choice(character_group)
        for character_group in character_groups
    ]

    characters.extend(
        secrets.choice(alphabet)
        for _ in range(PASSWORD_LENGTH - len(characters))
    )

    secrets.SystemRandom().shuffle(characters)

    return "".join(characters)


def request_password(name: str) -> str:
    while True:
        password = getpass.getpass(f"{name} password: ")
        confirmation = getpass.getpass(
            f"Confirm {name} password: "
        )

        if password != confirmation:
            print_error("Passwords do not match. Try again.")
            continue

        errors = validate_password(password)

        if errors:
            print_error("Invalid password:")

            for error in errors:
                print(f"   {RED}•{RESET} {error}")

            continue

        return password


def save_password(path: Path, password: str) -> None:
    path.write_text(password + "\n", encoding="utf-8")
    os.chmod(path, 0o600)


def secret_already_exists(path: Path) -> bool:
    return path.is_file() and path.stat().st_size > 0


def create_secrets(manual: bool) -> None:
    SECRETS_DIRECTORY.mkdir(parents=True, exist_ok=True)

    created_count = 0
    skipped_count = 0

    for name, path in SECRET_FILES.items():
        relative_path = path.relative_to(PROJECT_ROOT)

        if secret_already_exists(path):
            print_info(
                f"🔒 Secret already exists for "
                f"{BOLD}{name}{RESET}: {relative_path}. "
                "Skipping."
            )
            skipped_count += 1
            continue

        if path.exists():
            print_warning(
                f"Secret file for {BOLD}{name}{RESET} "
                "exists but is empty. It will be recreated."
            )

        if manual:
            password = request_password(name)
        else:
            password = generate_password()

        save_password(path, password)

        print_success(
            f"Created secret for {BOLD}{name}{RESET}: "
            f"{relative_path}"
        )

        created_count += 1

    print()

    if created_count > 0:
        print_success(
            f"Created {created_count} new secret file(s)."
        )

    if skipped_count > 0:
        print_info(
            f"Kept {skipped_count} existing secret file(s) unchanged."
        )

    if created_count == 0:
        print_info("All required secrets already exist.")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate local secrets for the Inception project."
    )

    parser.add_argument(
        "--manual",
        action="store_true",
        help="enter and validate passwords interactively",
    )

    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()

    print()
    print_info("Generating secrets for the Inception project...")
    print()

    try:
        validate_configuration()
        create_secrets(arguments.manual)
    except (OSError, ValueError) as error:
        print_error(str(error))
        raise SystemExit(1) from error

    print()
    print_info("New secret files receive permissions 600.")
    print_warning("Never add secret files to Git.")
    print()


if __name__ == "__main__":
    main()