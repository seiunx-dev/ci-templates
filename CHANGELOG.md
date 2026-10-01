# Changelog

本仓库按 [版本策略](README.md#版本策略) 发布：`v1.x.y` 不可变，`v1` 跟随最新的 `v1.x.y`。

## v1.1.0 — 2026-10-01

- **Docker 不再等测试**：`docker.yml` 新增 `defer-moving-tags`（默认 `false`，旧行为不变）和输出 `deferred-tags`；新增可复用工作流 `docker-retag.yml`。调用方去掉 docker job 的 `needs: [<测试>]`、设 `defer-moving-tags: true`，并在 `ci-ok` 之后加 `docker-tags` job。main 上构建完立刻推 `:sha-<sha>` / `:sha-<7>`（和 `:buildcache`），`:main` 等移动 tag 在 "CI OK" 通过后才重打到同一个 digest（不重建，带新旧 commit 顺序保护）。
  - **行为变化**（对启用的仓库）：`:main` 会比 `:sha-*` 晚到，晚到 "CI OK" 通过为止；测试失败的 commit 不会移动 `:main`，但会留下 `:sha-*` 镜像。需要尽早部署的环境 pin `:sha-<7>`。
  - Release 不变：release-gate 等 "CI OK"，`promote-on-tag` 重打 main 的镜像。
- **Sonar**：`sonar.yml` 默认忽略 `.github/workflows/**` 里的 githubactions:S7637（它要求 full SHA pin，会把每个 `@v1` 模板引用记成安全问题，Security Rating 掉到 C、quality gate 失败）。命令行参数会覆盖 properties 文件，所以模板读出 sonar-project.properties / `args` 里已有的 `sonar.issue.ignore.multicriteria` id 再追加 `ciTemplatesPins`。新 input `ignore-template-pins`（默认 `true`）可关闭。各仓库自己加的 S7637 忽略可以删掉。
- `sonar.yml` 的 `project-version` 支持 `auto`（读根目录 Cargo.toml / package.json / pyproject.toml）；参数构建步骤改为 Python，并有单元测试 `tests/sonar_args_test.py`。
- 自测：docker 推送路径（只推 `:sha-*` → 替身 CI OK → `docker-retag.yml` → 校验 digest 一致），镜像 `ghcr.io/seiunx-dev/ci-templates-selftest`；sonar 参数单元测试。

## v1.0.0 — 2026-10-01

首个版本。

- 可复用工作流：`rust-ci`、`go-ci`、`python-uv-ci`、`node-ci`、`sonar`、`docker`、`release-gate`、`rust-release`、`go-release`、`maturin-wheels`、`gh-release`、`pages`、`actionlint`。
- Composite actions：`setup-rust`、`apt-install`、`verify-version`、`wait-for-checks`、`package-archive`、`cargo-publish`。
- `tools/check_callers.py`：调用方 inputs/secrets 契约、timeout、SHA pin 检查；可直接检查调用方仓库。
- 自测 `self-test.yml`：在 Rust / Python / Go / npm / bun fixture 上实际运行模板。
