#!/usr/bin/env python3
"""Update ubuntu_iso_url and ubuntu_iso_sha256 for a given Ubuntu Server release.

This helper is meant to run from Renovate's post-upgrade tasks. It accepts the
target Ubuntu version (e.g. ``24.04.1`` or ``25.10``) and rewrites
``variables.auto.pkrvars.hcl`` so both the ISO download URL and its matching
SHA256 checksum point at that version.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import textwrap
import urllib.error
import urllib.request


BASE_URL = "https://releases.ubuntu.com"
ISO_TEMPLATE = "ubuntu-{version}-live-server-amd64.iso"
SHA_FILENAME = "SHA256SUMS"


def fetch_sha256(version: str) -> tuple[str, str]:
    """Return the ISO URL and SHA256 checksum for *version*.

    Raises ``RuntimeError`` if the checksum cannot be located.
    """

    iso_name = ISO_TEMPLATE.format(version=version)
    release_url = f"{BASE_URL}/{version}"
    sha_url = f"{release_url}/{SHA_FILENAME}"

    try:
        with urllib.request.urlopen(sha_url) as response:
            body = response.read().decode("utf-8", "replace")
    except urllib.error.URLError as exc:
        raise RuntimeError(f"unable to download {sha_url}: {exc}") from exc

    sha_line = next(
        (line.strip() for line in body.splitlines() if line.strip().endswith(iso_name)),
        None,
    )

    if sha_line is None:
        raise RuntimeError(
            textwrap.dedent(
                f"""
                could not locate {iso_name} in {sha_url}.
                Ensure the version exists and the server ISO is published.
                """
            ).strip()
        )

    checksum = sha_line.split()[0]
    iso_url = f"{release_url}/{iso_name}"
    return iso_url, checksum


def rewrite_variables_file(version: str, iso_url: str, checksum: str) -> None:
    variables_path = pathlib.Path("variables.auto.pkrvars.hcl")
    if not variables_path.exists():
        raise RuntimeError(f"{variables_path} does not exist")

    content = variables_path.read_text(encoding="utf-8")

    content, url_count = re.subn(
        r"^ubuntu_iso_url\s*=.*$",
        f'ubuntu_iso_url    = "{iso_url}"',
        content,
        flags=re.MULTILINE,
    )
    if url_count == 0:
        raise RuntimeError("failed to update ubuntu_iso_url")

    content, sha_count = re.subn(
        r"^ubuntu_iso_sha256\s*=.*$",
        f'ubuntu_iso_sha256 = "{checksum}"',
        content,
        flags=re.MULTILINE,
    )
    if sha_count == 0:
        raise RuntimeError("failed to update ubuntu_iso_sha256")

    variables_path.write_text(content, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Ubuntu version to target (e.g. 24.04.1)")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        iso_url, checksum = fetch_sha256(args.version)
        rewrite_variables_file(args.version, iso_url, checksum)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
