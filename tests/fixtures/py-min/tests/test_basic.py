import os
import socket

import pytest

from py_min import add, host_port


def test_add() -> None:
    assert add(2, 2) == 4


def test_host_port() -> None:
    assert host_port("redis://localhost:6379/0") == ("localhost", 6379)


@pytest.mark.skipif(
    os.environ.get("EXPECT_REDIS") != "1", reason="Redis service not requested"
)
def test_redis_reachable() -> None:
    with socket.create_connection(host_port(os.environ["CI_REDIS_URL"]), timeout=5):
        pass


def test_postgres_service_absent() -> None:
    """postgres-image is empty in the self-test, so the service must have been skipped."""
    if os.environ.get("EXPECT_NO_POSTGRES") != "1":
        pytest.skip("not asserted")
    with pytest.raises(OSError):
        socket.create_connection(
            host_port(os.environ["CI_POSTGRES_URL"]), timeout=2
        ).close()
