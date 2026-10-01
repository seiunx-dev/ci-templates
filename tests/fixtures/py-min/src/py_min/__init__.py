"""Fixture package for the ci-templates self-test."""

from urllib.parse import urlsplit


def add(a: int, b: int) -> int:
    return a + b


def host_port(url: str) -> tuple[str, int]:
    parts = urlsplit(url)
    if parts.hostname is None or parts.port is None:
        raise ValueError(f"no host:port in {url!r}")
    return parts.hostname, parts.port
