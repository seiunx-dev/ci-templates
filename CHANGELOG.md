# Changelog

本仓库按 [版本策略](README.md#版本策略) 发布：`v1.x.y` 不可变，`v1` 跟随最新的 `v1.x.y`。

## v1.1.7 — 2026-10-01

- `python-uv-ci.yml` 的 ruff 步骤：uv.lock 里有 ruff 时改为 `uvx ruff@<锁定版本>`，不再用 `uv run --frozen ruff`。`uv run` 只同步默认依赖组，ruff 写在 optional extra（如 `[project.optional-dependencies] dev`）里时根本没装，lint job 报 `Failed to spawn: ruff`（MejiroRina/lambda-sekai-asset-unpack）。现在不管 ruff 由哪个 extra / group 引入，用的都是锁定的版本；没有锁定时仍是 `uvx ruff`。py-min fixture 把 ruff 放进 optional extra `lint`，覆盖这种情况。

## v1.1.6 — 2026-10-01

- `go-ci.yml`：去掉工作流级的 `GOTOOLCHAIN: local`。setup-go 只在 `GOTOOLCHAIN` 还没被设成 `local` 时才读 go.mod 的 `toolchain` 行，于是一直装的是 `go` 行的版本：MejiroRina/sekai-diarkis（`go 1.25.0` + `toolchain go1.25.1`）的 CI 跑在 go1.25.0 上，发布却用 golang:1.25.1 构建。setup-go 选好版本后会自己导出 `GOTOOLCHAIN=local`，后续步骤仍不会下载别的工具链。`go-release.yml` 只在构建步骤上设置，本来就对。go-min fixture 改成 `go 1.27.0` + `toolchain go1.27.1`，新测试要求 `runtime.Version()` 等于 toolchain 行。（#11）
- `docker.yml` 新增 `build-record`（默认 `true`，行为不变）：`false` 时不上传 build-push-action 的 build record 构件（`.dockerbuild`）。私有仓库的构件按账号计存储配额，MejiroRina 的配额满了以后 SekaiColo 的 Release 连续 6 次在 upload-artifact 上失败。自测的两个 docker job 设为 `false`，新 job 检查本次 run 没有 `.dockerbuild` 构件。（#10）

## v1.1.5 — 2026-10-01

- `actions/verify-version`（release-gate）新增版本来源 `go`：读 Go 文件里赋给 `Version` 的字符串（默认 `version/version.go`；支持 `var Version = "..."`、`const Version = ...` 和 var 块里的 `Version = ...`），去掉开头的 tag 前缀后与 tag 比较。用于版本号写在 Go 源码、发布时再用 `-ldflags -X` 注入 tag 的仓库（Team-Haruki/Haruki-Toolbox-Backend 的 `version.Version = "v9.0.0-rc3"`）。`extra-paths` 里的 `.go` 文件同样按这个规则读取。其他来源不变。
- `tests/verify_version_test.sh` 覆盖 `go`（带 / 不带前缀、var 块 / 带类型的 const、extra path 不一致时失败）和 `none`。

## v1.1.4 — 2026-10-01

- `docker.yml`：`cache-backend: registry` 时，PR 构建也登录 GHCR（只读 `:buildcache`，仍然不推送）。私有仓库的镜像不能匿名读取，之前 PR 上缓存导入失败（`failed to fetch anonymous token`），每次都是冷构建（MejiroRina/kinagi-api 的 PR 构建 13 分钟，cargo-chef 的依赖层完全没用上）。同仓库 PR 登录失败会报错；fork 和 Dependabot 的 token 可能没有 `packages: read`，登录失败时只是退回无缓存构建。gha 缓存和 public 仓库不受影响。
- 自测的 PR docker 构建改用 registry 缓存，覆盖这一步。

## v1.1.3 — 2026-10-01

- `actions/verify-version`（release-gate）：只有 tag 的 **push** 事件才算发布（`is-tag=true`、输出 `tag`）。之前在 tag 上手动触发 `workflow_dispatch` 也会得到 `is-tag=true`，调用方的 promote 和 GitHub Release job 会真的发布，违背"dispatch = dry run"的约定。现在这种运行只打一条 notice，按 manifest 版本构建，不发布。tag push 的行为不变。
- 新增 `tests/verify_version_test.sh`（取 action 的脚本，覆盖 push / dispatch × tag / 分支），自测的 `yaml` job 会运行它。

## v1.1.2 — 2026-10-01

- `rust-release.yml` 新增 `require-build-secrets`：设为 true 时，`build-secret-names` 里任何一个变量为空（对应的 `build-secret-N` 没传）就在编译前失败，避免发布没有编译期密钥的二进制。只打印变量名，不打印值。（#4）

## v1.1.1 — 2026-10-01

- `docker-retag.yml`：写入后等 10 秒再检查一次（最多写 3 次）。两个 main run 几乎同时结束时，旧 commit 的 run 可能在新 run 写入前读到 tag、在它之后写入，把 `:main` 拨回旧 commit；新 run 的复查会发现并写回。不用 concurrency group，因为它会取消排队中的 job。
- 新增 `tests/docker_retag_test.sh`（桩掉 docker / gh，覆盖顺序保护的各分支），自测的 `yaml` job 会运行它。

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
