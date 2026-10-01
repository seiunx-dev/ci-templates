//! Fixture for the template self-test: rust-ci must run on Linux (with services, on the
//! runner and inside a container) and on Windows/macOS (without them).

pub fn add(a: u32, b: u32) -> u32 {
    a + b
}

/// `scheme://[user[:pass]@]host:port[/...]` -> `host:port`.
pub fn host_port(url: &str) -> Option<&str> {
    let rest = url.split_once("://")?.1;
    let rest = rest.rsplit_once('@').map_or(rest, |(_, r)| r);
    let hp = rest.split('/').next()?;
    hp.contains(':').then_some(hp)
}

#[cfg(test)]
mod tests {
    use std::net::TcpStream;
    use std::time::Duration;

    fn connect(var: &str) {
        let url = std::env::var(var).unwrap_or_else(|_| panic!("{var} is not set"));
        let hp = super::host_port(&url).expect("host:port in service URL");
        let addr = std::net::ToSocketAddrs::to_socket_addrs(hp)
            .expect("resolve service host")
            .next()
            .expect("one address");
        TcpStream::connect_timeout(&addr, Duration::from_secs(5)).expect("service port reachable");
    }

    #[test]
    fn adds() {
        assert_eq!(super::add(2, 2), 4);
    }

    #[test]
    fn parses_service_urls() {
        assert_eq!(
            super::host_port("postgres://postgres:postgres@localhost:5432/test"),
            Some("localhost:5432")
        );
        assert_eq!(super::host_port("redis://redis:6379/"), Some("redis:6379"));
    }

    #[test]
    #[ignore = "needs the Postgres service (CI_POSTGRES_URL)"]
    fn service_postgres_reachable() {
        connect("CI_POSTGRES_URL");
    }

    #[test]
    #[ignore = "needs the Redis service (CI_REDIS_URL)"]
    fn service_redis_reachable() {
        connect("CI_REDIS_URL");
    }
}
