# Changelog

本仓库按 [版本策略](README.md#版本策略) 发布：`v1.x.y` 不可变，`v1` 跟随最新的 `v1.x.y`。

## v1.0.0 — 2026-10-01

首个版本。

- 可复用工作流：`rust-ci`、`go-ci`、`python-uv-ci`、`node-ci`、`sonar`、`docker`、`release-gate`、`rust-release`、`go-release`、`maturin-wheels`、`gh-release`、`pages`、`actionlint`。
- Composite actions：`setup-rust`、`apt-install`、`verify-version`、`wait-for-checks`、`package-archive`、`cargo-publish`。
- `tools/check_callers.py`：调用方 inputs/secrets 契约、timeout、SHA pin 检查；可直接检查调用方仓库。
- 自测 `self-test.yml`：在 Rust / Python / Go / npm / bun fixture 上实际运行模板。
