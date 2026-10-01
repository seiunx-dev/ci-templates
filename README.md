# ci-templates

Team-Haruki / MejiroRina / seiunx-dev 共用的 GitHub Actions 模板：14 个可复用工作流（`on: workflow_call`）加 6 个 composite action。各仓库只保留很薄的调用文件（`ci.yml`、`release.yml`，文档站是 `docs.yml`），构建逻辑都在这里维护，改一处，所有仓库一起生效。

Shared reusable GitHub Actions workflows. Call them with `uses: seiunx-dev/ci-templates/.github/workflows/<name>.yml@v1`.

> 本仓库必须保持 **public**：别的 owner 名下的仓库（包括私有仓库）只能调用 public 仓库里的可复用工作流和 action。public 仓库不需要另外设置 "Access"，任何仓库都能调用。

## 目录

| 路径 | 作用 |
|---|---|
| `.github/workflows/rust-ci.yml` | fmt、clippy `-D warnings`、test（可切到 cargo-llvm-cov 出覆盖率）、可选 MSRV / Postgres / Redis / 容器 / apt |
| `.github/workflows/go-ci.yml` | gofmt、vet、staticcheck（带 `(compile)` 防护）、`go mod tidy -diff`、`test -race`（可同时出覆盖率并设阈值）、可选 bun 前端 |
| `.github/workflows/python-uv-ci.yml` | ruff check / format、`uv sync --locked`、测试（可做 Python 版本矩阵）、可选 `uv build` |
| `.github/workflows/node-ci.yml` | bun / npm / pnpm：lint、typecheck、test、build，外加带浏览器缓存的 Playwright e2e |
| `.github/workflows/sonar.yml` | 只做扫描：下载 `coverage-*` 构件后扫描，按下载到的文件自动传 `-Dsonar.*.reportPaths`；忽略 `.github/workflows/**` 里的 githubactions:S7637（`@v1` 引用），并和仓库已有的 multicriteria 合并；拿不到 `SONAR_TOKEN`（Dependabot、fork PR）时直接跳过，不报红 |
| `.github/workflows/docker.yml` | buildx 构建并推送到 GHCR。PR 只构建不推送；main 推 `:sha-<完整 sha>`、`:sha-<7 位>`，`:main` 默认一起推，设 `defer-moving-tags: true` 时留给 `docker-retag.yml` 在 "CI OK" 之后再移；tag 可以把 main 构建的镜像直接重打 tag（promote），不重建 |
| `.github/workflows/docker-retag.yml` | 把 `:main` 等移动 tag 指向已推送的 digest（`imagetools create`，不重建）；放在 `ci-ok` 之后，带新旧 commit 顺序保护 |
| `.github/workflows/release-gate.yml` | 发布的第一步：检查 tag 与 manifest 中的版本一致，并等待被打 tag 的 commit 上 "CI OK" 变绿 |
| `.github/workflows/rust-release.yml` | 按 target 矩阵构建（cargo / zigbuild / cross / ndk），打包成 tar.gz 或 zip 构件（保留 1 天） |
| `.github/workflows/go-release.yml` | 在单个 job 里交叉编译多平台并打包 |
| `.github/workflows/maturin-wheels.yml` | PyO3 wheel 和 sdist，附导入冒烟测试 |
| `.github/workflows/gh-release.yml` | 创建 GitHub Release：附加构件、生成 SHA256SUMS、处理 prerelease 和 latest |
| `.github/workflows/pages.yml` | 静态站：PR 只构建，push 到默认分支时部署到 Pages |
| `.github/workflows/actionlint.yml` | actionlint + shellcheck 检查工作流 |
| `.github/workflows/self-test.yml` | 本仓库自己的 CI（见“自测”） |
| `actions/setup-rust` | 装工具链（优先级：input > rust-toolchain.toml > stable）并配置 rust-cache（只在默认分支保存缓存） |
| `actions/apt-install` | apt 安装，带重试；在 runner 上用 sudo，在容器里不用 |
| `actions/verify-version` | 从 tag 或 manifest 解析版本并校验两者一致 |
| `actions/wait-for-checks` | 等待某个 commit 上的指定 check 完成并确认成功 |
| `actions/package-archive` | 跨平台打包（Linux / macOS / Windows） |
| `actions/cargo-publish` | 按顺序发布 crate，已发布的跳过，并等 index 可见后再发下一个 |
| `tools/check_callers.py` | 静态检查：YAML 语法、调用方传的 inputs/secrets 与模板声明是否对得上、每个 job 是否有 timeout、第三方 action 是否 pin 到 SHA |
| `tests/fixtures/` | 自测用的最小 Rust / Python / Go / npm / bun / Docker 项目 |
| `tests/sonar_args_test.py` | `sonar.yml` 参数构建步骤的单元测试（直接取工作流里的脚本运行） |
| `tests/docker_retag_test.sh` | `docker-retag.yml` 顺序保护的测试（取工作流里的脚本，桩掉 docker / gh） |
| `tests/verify_version_test.sh` | `actions/verify-version` 的事件 / ref 组合测试（只有 tag push 时 `is-tag=true`） |

## 怎么调用

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.pull_request.number) || format('{0}-{1}', github.event_name, github.sha) }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  rust:
    name: Rust
    uses: seiunx-dev/ci-templates/.github/workflows/rust-ci.yml@v1
    with:
      coverage: true
      postgres-image: postgres:17-alpine
      env: |
        MY_TEST_DSN=${CI_POSTGRES_URL}

  sonar:
    name: Sonar
    needs: [rust]
    uses: seiunx-dev/ci-templates/.github/workflows/sonar.yml@v1
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}   # 跨 owner 调用时 secrets: inherit 无效，必须显式传入

  docker:
    name: Docker           # 不 needs 测试：和测试并行，main 上只推 :sha-*
    permissions:
      contents: read
      packages: write
      pull-requests: read
    uses: seiunx-dev/ci-templates/.github/workflows/docker.yml@v1
    with:
      defer-moving-tags: true

  ci-ok:
    name: CI OK            # 分支保护里唯一的 required check
    if: always()
    needs: [rust, sonar, docker]
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')
        run: exit 1

  docker-tags:
    name: Docker tags      # CI OK 通过后才把 :main 移到这次的镜像，不重建
    needs: [docker, ci-ok]
    if: needs.docker.outputs.deferred-tags != ''
    permissions:
      contents: read
      packages: write
    uses: seiunx-dev/ci-templates/.github/workflows/docker-retag.yml@v1
    with:
      image: ${{ needs.docker.outputs.image }}
      digest: ${{ needs.docker.outputs.digest }}
      tags: ${{ needs.docker.outputs.deferred-tags }}
```

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags: ['v*']
  workflow_dispatch: # dry run: builds everything, publishes nothing

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  gate:
    name: Gate
    permissions:
      contents: read
      checks: read        # 被调用方要 checks: read，调用方 job 必须先给
    uses: seiunx-dev/ci-templates/.github/workflows/release-gate.yml@v1

  binaries:
    name: Binaries
    needs: gate
    uses: seiunx-dev/ci-templates/.github/workflows/rust-release.yml@v1
    with:
      version: ${{ needs.gate.outputs.version }}
      tag: ${{ needs.gate.outputs.tag }}

  github-release:
    name: GitHub Release
    needs: [gate, binaries]
    if: needs.gate.outputs.is-tag == 'true'
    permissions:
      contents: write
    uses: seiunx-dev/ci-templates/.github/workflows/gh-release.yml@v1
    with:
      tag: ${{ needs.gate.outputs.tag }}
      prerelease: ${{ needs.gate.outputs.prerelease }}
```

要点：

- **权限**：可复用工作流里 job 声明的权限不能超过调用方 job 给的权限。调用 `release-gate`（`checks: read`）、`docker`（`packages: write`）、`gh-release`（`contents: write`）、`pages`（`pages: write` + `id-token: write`）的 job 必须自己写 `permissions:`，否则运行时报 “nested job is requesting … but is only allowed …”。
- **secrets**：调用方与本仓库不在同一 owner 下，`secrets: inherit` 不会传任何东西，要逐个写。
- **PyPI / npm 发布** 不能在可复用工作流内部完成（trusted publishing 绑定的是调用方 workflow 文件），发布 job 写在调用方，用 `maturin-wheels` / `python-uv-ci` 上传的构件。
- **job 名**：调用方 job 的 `name` 会成为 check 名前缀（`Rust / Lint`、`Rust / Test`）。分支保护只要求 `CI OK`。

## 约定（已写进模板）

- **两个工作流**：`CI`（push main、pull_request main、workflow_dispatch）和 `Release`（push tags `v*`；workflow_dispatch 用作 dry run，构建全部产物但不发布任何东西，在 tag 上手动触发也一样：只有 tag 的 push 事件会发布）。
- **Docker 不等测试**（v1.1.0 起）：CI 里的 docker job 不 `needs` 测试，和测试并行，`defer-moving-tags: true`。main 上构建完立刻推不可变的 `:sha-<完整 sha>`、`:sha-<7 位>`（和 `:buildcache`）；`:main` 这类移动 tag 由 `ci-ok` 之后的 `docker-retag.yml` job 移过去（重打 tag，不重建），所以 `:main` 只会指向 "CI OK" 通过的 commit，但会比 `:sha-*` 晚到（晚多少取决于测试和 Sonar 比镜像构建慢多少）。部署要尽早拿到镜像就 pin `:sha-<7 位>`。测试失败的 commit 也会留下 `:sha-*` 镜像，但它没有 "CI OK"，release-gate 不会放行它的 tag。只有 docker 构建要用测试 job 产出的构件（`artifact-name`）时才保留 `needs`。
- **Release 不变**：release-gate 等被打 tag 的 commit 上 "CI OK" 变绿（docker 在 `ci-ok` 的 needs 里，所以 `:sha-<sha>` 一定已经在），`promote-on-tag` 再把它重打成 `:X.Y.Z` / `:X.Y` / `:latest`。
- **唯一的 required check 是 `CI OK`**：它是 `ci-ok` 聚合 job，`needs` 其余所有 job；有 job failure 或 cancelled 就失败，skipped 视为通过。
- **concurrency**：PR 用 `${workflow}-pr-<PR号>` 并 cancel-in-progress；其他事件用 `${workflow}-<事件>-<sha>`，每个 commit 一组。不能用 `ref` 分组：同组里排队中的 run 会被更新的 run 顶掉（即使 cancel-in-progress 是 false），连续 push 三次时中间那个 commit 就没有 "CI OK" 和 `:sha-<sha>` 镜像，给它打 tag 会让 gate 失败。Release 用 `release-${ref}`，从不取消。可复用工作流内部不定义 concurrency：被调用的工作流里 `github.workflow` 取到的是调用方的名字，自己再定义会和调用方的 group 撞上导致死锁。
- **权限**：顶层 `contents: read`。只有需要写权限的 job 才提权：Docker job 给 `packages: write`（PR 上不 login、不 push），发布 job 给 `contents: write`，PyPI/npm 发布 job 给 `id-token: write`，gate job 给 `checks: read`。
- **每个 job 都有 timeout-minutes**：检查类 15–20 分钟，覆盖率 30，Docker 45，Release 构建 45–60，发布 10。
- **缓存只从默认分支写**：rust-cache 用 `save-if`；Go 用 restore/save 两段式；docker 的 `cache-to` 只在默认分支上设置，gha 缓存按镜像名分 scope，重型 Rust 镜像用 registry `:buildcache`。PR 和 tag 只读缓存。rust-release 默认 `cache: false`：tag 上写不了缓存；需要热缓存时设 `cache: true`，并在 main 上手动跑一次 Release（dry run）预热。
- **构件保留期很短**：覆盖率 3 天，release 中间产物 1 天，docker build record 3 天。
- **版本号只写在 manifest 里**（Cargo.toml / pyproject / package.json），先提 bump PR，合并后再打 tag。gate 会拒绝 tag 与 manifest 不一致的发布。虚拟 workspace（根 Cargo.toml 没有版本）要设 `version-path` 或加 `[workspace.package] version`。
- **测试只跑一遍**：开启 coverage 时，测试本身就在 llvm-cov / `-coverprofile` / coverage.py 下运行，结果上传为 `coverage-<lang>` 构件，由 `sonar.yml` 下载后扫描。`extra-test-command` 跑 `--ignored` 测试时一定带测试名过滤。
- **服务**：`postgres-image` / `redis-image` 为空时服务不启动（GitHub 会跳过 `image: ''` 的服务容器）。测试通过 `CI_POSTGRES_URL` / `CI_REDIS_URL` 拿地址，用 `env:` 输入映射到项目自己的变量名（`MY_DSN=${CI_POSTGRES_URL}`）。容器模式（rust-ci `container:`）下主机名自动换成服务名。
- **Pin 策略**：第三方和官方 action 一律 pin 完整 SHA，并在后面注释 `# vX.Y.Z`，由 Dependabot（github-actions 生态，分组）统一升级。各仓库引用本模板时用 `@v1`。
- **Rust 工具链**：用 `rust-toolchain.toml` 固定版本，并和 Dockerfile 的 `rust:<ver>` 同步升级。

## 版本策略

- `v1.x.y`：**不可变** tag，每次发布打一个，永不移动、永不删除。
- `v1`：**移动的大版本 tag**，始终指向最新的 `v1.x.y`。调用方用 `@v1`，自动拿到修复。
- 兼容的改动（新增 input 且默认值保持原行为、修 bug、升级 pin）→ 发 `v1.x.y` 并移动 `v1`。
- 不兼容的改动（删除或改名 input、改默认行为、改构件名）→ 发 `v2.0.0` 和 `v2`；`v1` 不再前进（只回补安全修复）。
- 模板内部引用 composite action 用的是 `seiunx-dev/ci-templates/actions/<name>@v1`，所以调用方即使 pin 到 `@v1.2.3` 或 commit SHA，composite action 仍然跟随 `v1`。需要完全冻结的仓库只能 fork。
- 每次发布在 `CHANGELOG.md` 记一节，并创建同名 GitHub Release。

### 发布本仓库

1. PR 合并到 main，等 `CI` 变绿（自测会用本 commit 的工作流文件跑一遍 fixture）。
2. 改 `CHANGELOG.md`，然后：
   ```sh
   git tag -a v1.2.3 -m "v1.2.3"
   git tag -fa v1 -m "v1 -> v1.2.3" v1.2.3^{}
   git push origin v1.2.3
   git push -f origin v1
   gh release create v1.2.3 --notes-file <notes>
   ```
3. 改了 `actions/` 下的 composite action 时：自测里模板引用的 action 是已发布的 `@v1`，看不到本次修改。先把 `v1` 移到新 commit，再在 main 上手动跑一次 `CI`（workflow_dispatch）确认，最后补打 `v1.x.y`。等合并触发的 push run 结束后再手动触发：同一 commit 的两个 run 同时跑时，各自重建并推 `:sha-<sha>`（digest 不同），自测的 docker 检查会失败。同一 commit 再跑一次是允许的：分支 tag 已经指向这个 commit 时 `docker-retag.yml` 不再移动，自测按"已持有"检查。

## 自测

`self-test.yml`（工作流名 `CI`）在 push / PR / workflow_dispatch 时：

- actionlint + shellcheck 检查所有工作流；`tools/check_callers.py` 解析所有 YAML 并检查本仓库内的调用；
- 以 `./.github/workflows/x.yml` 调用本 commit 的模板，跑 `tests/fixtures/` 下的最小项目：
  - rust-ci：Windows、macOS、Linux + Postgres + coverage + MSRV、Debian 容器 + Redis（服务通过服务名访问）；
  - python-uv-ci：3.12/3.13 矩阵 + Redis + `uv build`；go-ci：Postgres + 覆盖率阈值；node-ci：npm、bun + 覆盖率；
  - 服务测试会真的连一次端口，并断言 `image: ''` 的那个服务没有启动；
  - sonar：不传 token，验证跳过路径是绿的；release-gate：dry run；
  - rust-release：cargo（linux/macOS/Windows）+ zigbuild（glibc 2.17），随后检查产物文件名、tar.gz/zip、dir/flat 布局、额外文件和 glibc 符号版本；
  - docker：PR 上构建 amd64 + arm64（不登录、不推送，覆盖 pr-paths 过滤）；push main 和 workflow_dispatch 时走 `defer-moving-tags` 推送路径，镜像是一次性的 `ghcr.io/seiunx-dev/ci-templates-selftest`：先检查 `:sha-*` 已推、分支 tag 没动，过一个替身 "CI OK" job，再用 `docker-retag.yml` 移分支 tag，最后检查分支 tag 指向同一个 digest（没有重建）；pages：只构建（`deploy: false`）。
  - sonar：`tests/sonar_args_test.py` 单元测试参数构建（multicriteria 合并、properties 语法、`project-version: auto`、report paths）。
- 不在自测里跑：`gh-release.yml`（会建 release）、`maturin-wheels.yml`（慢，由首个试点仓库覆盖）、`go-release.yml`（需要 go.mod 在仓库根目录）、docker 的 promote 路径。`docker-retag.yml` 的顺序保护（tag 指向更旧 / 更新 / 同一 commit、并发覆盖后重写、关闭检查）由 `tests/docker_retag_test.sh` 用桩掉的 docker / gh 覆盖；`verify-version` 的事件 / ref 组合（只有 tag push 发布）由 `tests/verify_version_test.sh` 覆盖。

## 迁移前检查

```sh
# 检查一个仓库的 .github/workflows/*.yml 调用是否和模板声明对得上
python3 tools/check_callers.py path/to/repo
# 或单个文件
python3 tools/check_callers.py path/to/ci.yml
# 批量：DIR/<owner>__<repo>/*.yml 形式的调用文件集合；--clones 再检查它们引用的脚本 / Dockerfile 在仓库里真实存在
python3 tools/check_callers.py --callers DIR --clones CLONES_DIR
```

调用方仓库自己的 CI 里建议加上 `actionlint.yml`：

```yaml
  lint:
    name: Workflow lint
    uses: seiunx-dev/ci-templates/.github/workflows/actionlint.yml@v1
```

## 已知限制

- PyPI trusted publishing、npm provenance 不能在可复用工作流内部完成，发布 job 留在调用方。trusted publisher 绑定的是 **workflow 文件名**：发布从别的文件挪到 release.yml 的仓库，要在第一次打 tag 之前到 PyPI 为 release.yml（environment `pypi`）新增 trusted publisher。
- `sonar.yml` 用命令行 `-Dsonar.issue.ignore.multicriteria=...` 加 S7637 的忽略，命令行会覆盖 sonar-project.properties 里的同名键，所以模板先读出 properties（或 `-Dproject.settings=` 指定的文件）和 `args` 里已有的 id 再追加 `ciTemplatesPins`。只在 SonarQube Cloud 网页上配置的 multicriteria 读不到，会被这次扫描的参数盖掉；这类规则要写进 sonar-project.properties。
- `docker-retag.yml` 的顺序保护靠镜像的 `org.opencontainers.image.revision` label 和 compare API。两个 main run 几乎同时移同一个 tag 时，旧 commit 的 run 可能在新 run 写入前读到旧值、在它之后写入；所以每次写入后等 10 秒再检查一次（最多写 3 次），新 run 发现被旧 commit 覆盖会再写回去。没有用 concurrency group：它会取消排队中的 job。镜像没有 revision label、或 compare API 判断不了先后时，只在第一轮移动。
- `docker.yml` 的 `latest: auto` 用 `git ls-remote` 找最高 semver tag；私有仓库匿名 ls-remote 会失败，此时回退为“稳定 tag 一律打 latest”。补打旧版本的 tag 时，私有仓库要显式传 `latest: false`。（自测在 public 仓库里，测不到这条路径。）
- 已在 GitHub 上实测：`image: ''` 的服务容器会被跳过（日志："will not be started because the container definition has an empty image"），`container: ''` 的 job 直接跑在 runner 上。
- 服务容器和 `container:` 只在 Linux runner 上可用。rust-ci 在没有服务和容器时走不带 `services:`/`container:` 的 job 变体，所以同一模板能跑 Windows/macOS；两个变体的步骤通过 YAML anchor 共用。

## Inputs 参考

下面的表由各文件的 `workflow_call` / `action.yml` 声明整理；以文件为准。

### `rust-ci.yml` — Rust CI

Jobs：`Lint`（fmt + 每个 feature set 跑 clippy `-D warnings`）、`Test`（cargo test 或 cargo-llvm-cov，上传 `coverage-<cache-key-prefix>`）、可选 `MSRV`。设了 `postgres-image` / `redis-image` / `container` 时走带 `services:`/`container:` 的变体（仅 Linux）。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `working-directory` | string | `.` | Main Cargo project directory. |
| `extra-directories` | string | `''` | Other standalone Cargo projects (not workspace members) that get fmt/clippy/test too, one per line. |
| `toolchain` | string | `''` | Toolchain override. Empty = rust-toolchain.toml channel, else stable. Prefer committing rust-toolchain.toml. |
| `targets` | string | `''` | Extra rustup targets (comma-separated), e.g. wasm32-unknown-unknown for extra-lint-command. |
| `cargo-args` | string | `--workspace` | Package selection passed to clippy and test (e.g. --workspace, -p foo). |
| `feature-sets` | string | `default` | Feature flag sets to lint, one per line. `default` = no extra flags. e.g. "default\n--no-default-features --features nuverse-auth\n--all-features". |
| `test-feature-sets` | string | `default` | Feature flag sets to test, one per line (same syntax as feature-sets). |
| `test-args` | string | `''` | Extra cargo test arguments before `--` (e.g. --lib --bins). |
| `test-harness-args` | string | `''` | Arguments after `--` for the test harness (e.g. --test-threads=1). |
| `extra-test-command` | string | `''` | Shell run after the main tests with the services up. $CARGO_TEST is `cargo test` or `cargo llvm-cov --no-report` (coverage mode), e.g. `$CARGO_TEST --locked --lib -- --ignored --test-threads=1 db::tests postgres`. Always pass a test-name filter: a bare `--ignored` also runs network, credential and memory-probe tests that are ignored for a reason. |
| `extra-lint-command` | string | `''` | Shell run at the end of the lint job (e.g. a wasm32 check, cargo doc, cargo audit). |
| `fmt` | boolean | `true` | Run cargo fmt --check. |
| `coverage` | boolean | `false` | Run tests under cargo-llvm-cov and upload coverage/lcov-rust.info. |
| `coverage-fail-under-lines` | string | `''` | Minimum line coverage percentage (empty = no gate). |
| `cargo-llvm-cov-version` | string | `0.9.0` | cargo-llvm-cov version installed by taiki-e/install-action. |
| `msrv` | string | `''` | If set (e.g. 1.85), an extra job runs `cargo check --locked` on that toolchain. |
| `postgres-image` | string | `''` | Postgres service image (e.g. postgres:17-alpine). Empty = no service. |
| `redis-image` | string | `''` | Redis service image (e.g. redis:7-alpine). Empty = no service. |
| `container` | string | `''` | Run both jobs in this container image (e.g. debian:trixie-slim for system libs). Empty = on the runner. |
| `apt-packages` | string | `''` | Debian/Ubuntu packages to install first (e.g. "clang pkg-config libavcodec-dev"). |
| `submodules` | string | `false` | actions/checkout submodules (false \| true \| recursive). |
| `setup-command` | string | `''` | Shell hook run after checkout and toolchain setup (e.g. fetch a pinned C++ engine). |
| `env` | string | `''` | KEY=VALUE lines exported to both jobs. ${CI_POSTGRES_URL} and ${CI_REDIS_URL} are substituted with the service URLs. |
| `cache-key-prefix` | string | `rust` | Prefix for rust-cache keys and the coverage artifact name. Change it when one repo calls rust-ci more than once. |
| `runs-on` | string | `ubuntu-latest` | Runner label. |
| `lint-timeout-minutes` | number | `20` | lint / MSRV job 的超时（分钟）。 |
| `test-timeout-minutes` | number | `30` | test job 的超时（分钟）。 |

### `go-ci.yml` — Go CI

Jobs：`Lint`（gofmt、`go mod tidy -diff`、build、vet、staticcheck、可选 govulncheck）、`Test`（`go test -race`，可同时出 `coverage/go.out` 并设阈值，上传 `coverage-go`）、可选 `Frontend`（bun）。`GOTOOLCHAIN=local`，Go 版本取自 go.mod。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `working-directory` | string | `.` | 项目目录（相对仓库根）。 |
| `go-version-file` | string | `go.mod` | File that pins the Go version (go.mod or .go-version). |
| `build-flags` | string | `-mod=readonly` | Flags for go build/vet/test (e.g. -mod=readonly). |
| `staticcheck` | string | `auto` | auto (go tool staticcheck if go.mod declares it, else go run @staticcheck-version) \| off |
| `staticcheck-version` | string | `2026.2` | `go run honnef.co/go/tools/cmd/staticcheck@<version>` 用的版本（go.mod 未声明 staticcheck tool 时）。 |
| `staticcheck-command` | string | `''` | Full override, e.g. "go run -modfile=.github/tools/go.mod honnef.co/go/tools/cmd/staticcheck". |
| `govulncheck` | boolean | `false` | Run govulncheck (golang.org/x/vuln/cmd/govulncheck@latest). |
| `tidy-check` | boolean | `true` | Fail when go mod tidy would change go.mod/go.sum. |
| `race` | boolean | `true` | go test 加 -race。 |
| `test-packages` | string | `./...` | go test 的包模式。 |
| `test-args` | string | `-count=1` | go test 额外参数。 |
| `coverage` | boolean | `false` | Write coverage/go.out (atomic) from the same race test run and upload coverage-go. |
| `coverpkg-exclude` | string | `''` | Regex of packages to leave out of -coverpkg (e.g. /database/ent). Empty = default coverpkg. |
| `coverage-threshold` | string | `''` | Minimum total statement coverage percent (empty = no gate). |
| `postgres-image` | string | `''` | Postgres 服务镜像（如 postgres:17-alpine），空 = 不启动。测试拿到 CI_POSTGRES_URL。 |
| `redis-image` | string | `''` | Redis 服务镜像（如 redis:7-alpine），空 = 不启动。测试拿到 CI_REDIS_URL。 |
| `env` | string | `''` | KEY=VALUE lines for the test job. ${CI_POSTGRES_URL} / ${CI_REDIS_URL} are substituted. |
| `frontend-directory` | string | `''` | Directory of a bun frontend to check (empty = no frontend job). |
| `bun-version` | string | `''` | Bun version for the frontend (e.g. 1.3.14). Empty = bun-version-file or package.json packageManager. |
| `frontend-commands` | string | `bun run build` | Commands run in the frontend directory after `bun install --frozen-lockfile`, one per line. |
| `runs-on` | string | `ubuntu-latest` | Runner 标签。 |
| `timeout-minutes` | number | `20` | job 超时（分钟）。 |

### `python-uv-ci.yml` — Python CI

Jobs：`Lint`（ruff check/format；项目锁了 ruff 就用项目的，否则 `uvx ruff`；可选额外 lint；可选 `uv build` 上传 `dist`）、`Test <python>`（`uv sync`，跑 `test-command`，可选上传 `coverage-python`）。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `working-directory` | string | `.` | 项目目录（相对仓库根）。 |
| `python-versions` | string | `[""]` | JSON list of Python versions for the test job, e.g. '["3.12"]' or '["3.14t"]'. '[""]' = .python-version / requires-python. |
| `uv-version` | string | `''` | uv version (empty = setup-uv default / required-version in pyproject). |
| `sync-args` | string | `--locked --all-extras --dev` | Arguments for uv sync. |
| `ruff` | boolean | `true` | Run ruff check and ruff format --check (uses the project's ruff if it is a dependency, else uvx ruff). |
| `lint-command` | string | `''` | Extra lint command (e.g. "uv run mypy src"). |
| `test-command` | string | `uv run pytest` | Test command; empty = no test job. e.g. "uv run pytest -n auto". |
| `coverage-path` | string | `''` | Coverage file the test command writes (e.g. coverage/python.xml); uploaded as coverage-python. |
| `download-artifact` | string | `''` | Workflow artifact (same run) downloaded into ./ci-artifacts before sync, e.g. a native wheel. |
| `setup-command` | string | `''` | Shell hook after uv sync (e.g. install a downloaded wheel, repair a native lib). |
| `apt-packages` | string | `''` | 先安装的 apt 包（空格或换行分隔）。 |
| `postgres-image` | string | `''` | Postgres 服务镜像（如 postgres:17-alpine），空 = 不启动。测试拿到 CI_POSTGRES_URL。 |
| `redis-image` | string | `''` | Redis 服务镜像（如 redis:7-alpine），空 = 不启动。测试拿到 CI_REDIS_URL。 |
| `env` | string | `''` | KEY=VALUE lines. ${CI_POSTGRES_URL} / ${CI_REDIS_URL} are substituted. |
| `build-dist` | boolean | `false` | Run `uv build` and upload dist/ as artifact `dist` (retention 3 days). |
| `runs-on` | string | `ubuntu-latest` | Runner 标签。 |
| `timeout-minutes` | number | `20` | job 超时（分钟）。 |

### `node-ci.yml` — Node CI

Jobs：`Check`（按 lockfile 判断 bun/npm/pnpm，frozen 安装后跑 lint → typecheck → test → build；`auto` = package.json 里有该 script 才跑）、可选 `E2E`（Playwright，浏览器按版本缓存）。覆盖率上传为 `coverage-js`（lcov-js.info）。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `working-directory` | string | `.` | 项目目录（相对仓库根）。 |
| `package-manager` | string | `auto` | auto (from lockfile) \| bun \| npm \| pnpm |
| `node-version` | string | `''` | Node version (also used with bun for tools that need node). Empty = .nvmrc / .node-version when present, else 24. |
| `bun-version` | string | `''` | Bun version (e.g. 1.3.14). Empty = .bun-version or package.json packageManager. |
| `install-command` | string | `''` | Override the install command (default = frozen-lockfile install for the package manager). |
| `lint-command` | string | `auto` | auto（有 lint 脚本就跑）/ 显式命令 / '' 跳过。 |
| `typecheck-command` | string | `auto` | auto（有 typecheck 脚本就跑）/ 显式命令 / '' 跳过。 |
| `test-command` | string | `auto` | auto runs the `test` script. For coverage, pass e.g. `bun test --coverage --coverage-reporter=lcov --coverage-dir=coverage`. |
| `build-command` | string | `auto` | 构建命令（node-ci: auto / 显式 / ''）。 |
| `coverage-path` | string | `''` | Coverage file to upload as coverage-js (e.g. coverage/lcov.info). It is renamed to lcov-js.info. |
| `e2e-command` | string | `''` | Playwright command (empty = no e2e job), e.g. "bunx playwright test". |
| `e2e-prepare-command` | string | `''` | Shell run before the e2e command (e.g. a build the tests serve). |
| `e2e-browsers` | string | `chromium` | Playwright browsers to install (space-separated). |
| `e2e-xvfb` | boolean | `false` | Wrap the e2e command in xvfb-run (headed WebGL tests). |
| `upload-build` | string | `''` | Path of build output to upload as artifact `build` (retention 3 days). Empty = no upload. |
| `runs-on` | string | `ubuntu-latest` | Runner 标签。 |
| `timeout-minutes` | number | `15` | job 超时（分钟）。 |
| `e2e-timeout-minutes` | number | `20` | e2e job 的超时（分钟）。 |

### `sonar.yml` — Sonar

Job：`Scan`。只下载 `coverage-*` 构件并扫描；无 token 时绿色跳过。调用方必须显式传 `SONAR_TOKEN`。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `coverage-pattern` | string | `coverage-*` | Artifact name pattern to download into coverage/ (empty = none). |
| `project-version` | string | `''` | sonar.projectVersion。空 = 不传；`auto` = 读根目录 Cargo.toml（`[package]` 或 `[workspace.package]`）/ package.json / pyproject.toml 的版本。不要写死在 sonar-project.properties 里。 |
| `args` | string | `''` | Extra scanner arguments (e.g. -Dsonar.qualitygate.wait=true). |
| `report-paths` | boolean | `true` | Pass the report path of every downloaded coverage file (see header). |
| `ignore-template-pins` | boolean | `true` | 忽略 `.github/workflows/**` 里的 githubactions:S7637（要求 full SHA pin），`@v1` 模板引用不再拉低 Security Rating；和仓库已有的 multicriteria 合并（见“已知限制”）。 |
| `timeout-minutes` | number | `15` | job 超时（分钟）。 |

secrets: `SONAR_TOKEN`

### `docker.yml` — Docker

Job：`Build and push`。调用方 job 权限：`contents: read`、`packages: write`、`pull-requests: read`。tag 规则：分支、PR、`sha-<long>`、`sha-<short>`、tag 上的 `X.Y.Z` / `X.Y` / `latest`。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `image` | string | `''` | Full image name. Empty = ghcr.io/<owner>/<repo> lowercased. |
| `context` | string | `.` | docker build context。 |
| `file` | string | `''` | Dockerfile path. Empty = <context>/Dockerfile. |
| `target` | string | `''` | Dockerfile 多阶段构建的 target。 |
| `platforms` | string | `linux/amd64` | e.g. linux/amd64 or linux/amd64,linux/arm64 (QEMU is set up for non-amd64). |
| `build-args` | string | `''` | Extra build args, one KEY=VALUE per line. |
| `version-build-arg` | string | `''` | Name of a build arg that receives the version (tag without prefix, or <branch>-<sha7>). Empty = none. Avoid declaring it early in the Dockerfile: it busts every later layer. |
| `tag-prefix` | string | `v` | Git tag prefix for release tags (v, engine-v, ...). |
| `latest` | string | `auto` | auto (stable tag that is the highest semver tag with this prefix) \| true \| false |
| `extra-tags` | string | `''` | Extra docker/metadata-action tag rules, one per line. |
| `defer-moving-tags` | boolean | `false` | 分支 push 只推 `:sha-*`，移动 tag（`:<branch>`、非 sha 的 extra tag）放进 `deferred-tags` 输出，由 `docker-retag.yml` 在 CI OK 之后移。PR 和 tag push 不受影响。 |
| `promote-on-tag` | boolean | `false` | On tag pushes, re-tag the :sha-<sha> image instead of rebuilding. |
| `promote-wait-minutes` | number | `0` | How long to wait for the :sha-<sha> image to appear before building instead. |
| `pr-paths` | string | `''` | Glob patterns (one per line, ** allowed). When set, PR builds run only if a matching file changed. |
| `cache-backend` | string | `gha` | gha \| registry \| none |
| `cache-mode` | string | `min` | min \| max (max also caches intermediate stages, e.g. cargo-chef cook) |
| `provenance` | string | `false` | build-push-action provenance (false keeps GHCR free of unknown/unknown manifests). |
| `sbom` | string | `false` | build-push-action 的 sbom。 |
| `artifact-name` | string | `''` | Same-run workflow artifact to download before the build (e.g. prebuilt binaries). Supports a glob pattern. |
| `artifact-path` | string | `dist` | Where to put the downloaded artifact (relative to the repo root). |
| `artifact-merge` | boolean | `true` | Merge multiple matching artifacts into artifact-path (false = one sub-directory per artifact). |
| `prepare-command` | string | `''` | Shell run after checkout and the artifact download, before the build (e.g. lay out a binary context). |
| `submodules` | string | `false` | actions/checkout 的 submodules（false / true / recursive）。 |
| `runs-on` | string | `ubuntu-latest` | Runner 标签。 |
| `timeout-minutes` | number | `45` | job 超时（分钟）。 |

outputs: `image`, `digest`, `version`, `deferred-tags`（没推的移动 tag，每行一个完整引用；没有则为空）

### `docker-retag.yml` — Docker retag

Job：`Move tags`。调用方 job 权限：`contents: read`、`packages: write`。用 `docker buildx imagetools create` 把 tag 指向已在 registry 里的 digest，不重建。放在 `ci-ok` 之后（`needs: [docker, ci-ok]`，`if: needs.docker.outputs.deferred-tags != ''`）。移动前读出 tag 当前镜像的 `org.opencontainers.image.revision`，用 compare API 判断：已经指向更新的 commit 就跳过（并发的 main run 乱序结束时不会把 `:main` 往回拨）。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `image` | string | `''` | 镜像名。空 = ghcr.io/<owner>/<repo>（小写）。 |
| `digest` | string | `''` | 要打 tag 的 digest（sha256:...）。空 = 本 commit 的 `:sha-<sha>`。 |
| `tags` | string | 必填 | 每行一个 tag，完整引用（image:tag）或只写 tag 名。 |
| `registry` | string | `''` | 登录的 registry。空 = `image` 的 host 部分。 |
| `check-ancestry` | boolean | `true` | tag 已指向更新的 commit 构建的镜像时跳过。 |
| `timeout-minutes` | number | `10` | job 超时（分钟）。 |

outputs: `moved`（实际移动的 tag，每行一个）

### `release-gate.yml` — Release gate

Job：`Gate`。调用方 job 权限：`contents: read`、`checks: read`。outputs 供后续 job 使用：`version`、`tag`、`is-tag`（只有 tag 的 push 事件为 `true`；dry run 为 `false`，包括在 tag 上手动 workflow_dispatch）、`prerelease`。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `version-source` | string | `cargo` | cargo \| pyproject \| package-json \| file \| none |
| `version-path` | string | `''` | Manifest path (default per source). |
| `version-extra-paths` | string | `''` | Other manifests that must carry the same version, one per line. |
| `tag-prefix` | string | `v` | tag 前缀（v、engine-v ...）。 |
| `require-check` | string | `CI OK` | Check run that must be green on the tagged commit. Empty = do not wait. |
| `wait-minutes` | number | `30` | Maximum wait for the check (the job itself times out at 60). |

outputs: `version`, `tag`, `is-tag`, `prerelease`

### `rust-release.yml` — Rust release

Job：`Build <label>`（每个 target 一个）。产物：构件 `release-<label>`（`<asset>.tar.gz` 或 `.zip`），可选 `bin-<label>`。`targets` 每项字段：`label`、`os`、`target`（必填），`builder`（cargo / zigbuild / cross / ndk）、`bins`、`features`、`files`、`extra-files`、`format`、`layout`、`apt`。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `version` | string | **必填** | Release version (from release-gate). |
| `tag` | string | `''` | Release tag (from release-gate; empty on dry runs). |
| `name` | string | `''` | Asset base name. Empty = repository name lowercased. |
| `bins` | string | `''` | Binary names to package, one per line or space-separated. Empty = `name`. |
| `targets` | string | 见文件头 | JSON list of targets (see header). |
| `cargo-args` | string | `''` | Extra cargo build args (e.g. -p my-crate). |
| `features` | string | `''` | Feature flags for every target (e.g. --features media-ffi). |
| `profile` | string | `release` | cargo profile（release / dev / 自定义）。 |
| `toolchain` | string | `''` | Toolchain override (empty = rust-toolchain.toml, else stable). |
| `cache` | boolean | `false` | Restore the per-target rust-cache (see header). Default off. |
| `extra-cache-path` | string | `''` | Extra path cached with actions/cache (e.g. a prebuilt compiler plugin). Restored always, saved only on the default branch. |
| `extra-cache-key` | string | `''` | Key for extra-cache-path; the runner OS and arch are appended. |
| `zig-version` | string | `0.15.2` | Zig used by the zigbuild builder (pinned; build.rs scripts may call zig directly). |
| `cargo-zigbuild-version` | string | `0.23.4` | zigbuild builder 用的 cargo-zigbuild 版本（固定）。 |
| `build-env` | string | `''` | KEY=VALUE lines exported to the build step; {version} and {tag} are substituted. |
| `build-secret-names` | string | `''` | Comma-separated env var names that receive secrets build-secret-1..3, in order (compile-time secrets). |
| `require-build-secrets` | boolean | `false` | Fail the build step before compiling if any env var named in `build-secret-names` is empty (its `build-secret-N` was not passed). For compile-time secrets that must be baked in. |
| `build-command` | string | `''` | Replace cargo build entirely (custom toolchains). Env: TARGET, LABEL, VERSION, PROFILE, BIN_DIR. The command must put the binaries into $BIN_DIR. |
| `setup-command` | string | `''` | Shell hook before the build (e.g. fetch a pinned C++ engine). |
| `apt-packages` | string | `''` | apt packages for Linux runners. |
| `submodules` | string | `false` | actions/checkout 的 submodules（false / true / recursive）。 |
| `extra-files` | string | `''` | Files added to every archive, one per line (`src=>dest` renames). |
| `asset-name` | string | `{name}-{version}-{label}` | Archive name template: {name} {version} {tag} {label} {target}. |
| `layout` | string | `dir` | dir (files under a top-level folder) \| flat (files at archive root) |
| `upload-binaries` | boolean | `false` | Also upload raw binaries as artifact bin-<label> (e.g. for a thin Docker image built from them). |
| `timeout-minutes` | number | `60` | job 超时（分钟）。 |

secrets: `build-secret-1`, `build-secret-2`, `build-secret-3`

### `go-release.yml` — Go release

Job：`Build`。产物：构件 `release-go`，可选 `bin-go`。`binaries` 每行 `name=./cmd/name`。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `version` | string | **必填** | 发布版本（来自 release-gate）。 |
| `tag` | string | `''` | 发布 tag（来自 release-gate；dry run 时为空）。 |
| `binaries` | string | `''` | name=package lines. Empty = <repo name>=. . |
| `platforms` | string | `linux/amd64 linux/arm64` | GOOS/GOARCH list, space-separated. |
| `ldflags` | string | `-s -w -X {module}/version.Version={tag}` | go build -ldflags，可用 {version} {tag} {commit} {date} {module}。 |
| `cgo` | string | `0` | CGO_ENABLED。 |
| `go-version-file` | string | `go.mod` | 固定 Go 版本的文件（go.mod 或 .go-version）。 |
| `extra-files` | string | `''` | Files added to every archive, one per line (`src=>dest` renames). |
| `asset-name` | string | `{name}-{label}` | Archive name template: {name} {version} {tag} {os} {arch} {label} (label = os-arch). |
| `layout` | string | `flat` | flat (files at archive root) \| dir |
| `build-command` | string | `''` | Replace the built-in build (must write archives to ./dist). Env: VERSION, TAG. |
| `upload-binaries` | boolean | `false` | Also upload raw binaries as artifact bin-go (dist-bin/<os>-<arch>/...). |
| `timeout-minutes` | number | `20` | job 超时（分钟）。 |

### `maturin-wheels.yml` — Maturin wheels

Jobs：每个 target × variant 一个 wheel job（构件 `wheels-<variant>-<label>`），可选 `sdist`（`wheels-sdist-<variant>`）。abi3 crate 用默认 `interpreters`；非 abi3 用 `find` + `setup-python-versions`。`targets` 每项字段：`label`、`os`、`target`，可选 `manylinux`、`interpreters`、`test`。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `working-directory` | string | `.` | Directory with pyproject.toml (maturin project). |
| `targets` | string | 见文件头 | JSON target 列表（字段见文件头）。 |
| `variants` | string | `[""]` | JSON list of package variants; each job gets WHEEL_VARIANT for configure-command. '[""]' = single package. |
| `configure-command` | string | `''` | Shell run before building (e.g. rewrite the package name per variant). Env WHEEL_VARIANT, VERSION. |
| `version` | string | `''` | Version passed to configure-command as VERSION. |
| `interpreters` | string | `''` | "" (maturin default, abi3) \| "find" (--find-interpreter) \| space-separated list for -i. See header. |
| `setup-python-versions` | string | `''` | Extra Pythons installed on macOS/Windows runners before the build (space- or newline-separated), e.g. "3.9 3.10 3.11 3.12 3.13 3.14 3.14t" together with interpreters "find". Linux builds use the manylinux container's interpreters and ignore this. |
| `args` | string | `''` | Extra maturin build args (e.g. --features python). |
| `manylinux` | string | `auto` | manylinux 策略（auto / 2_28 / musllinux_1_2 ...）。 |
| `before-script-linux` | string | `''` | Script run inside the manylinux container before building (system deps). {target} and {variant} are substituted, e.g. `if [ "{variant}" = skia ]; then bash deps.sh {target}; fi`. |
| `sdist` | boolean | `true` | 同时构建 sdist。 |
| `smoke-import` | string | `''` | Module to import after installing the built wheel (empty = no smoke test). |
| `test-command` | string | `''` | Shell run after the smoke install (working-directory), e.g. "pip install pytest && pytest tests". Needs smoke-import. |
| `python-version` | string | `3.13` | Python used for the smoke test. |
| `timeout-minutes` | number | `45` | job 超时（分钟）。 |

### `gh-release.yml` — GitHub Release

Job：`Publish`。调用方 job 权限：`contents: write`。下载 `artifact-pattern` 匹配的构件，生成 SHA256SUMS，创建/更新 release；带 `-` 的版本是 prerelease 且不设 latest。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `tag` | string | **必填** | Tag to publish (usually needs.gate.outputs.tag). |
| `prerelease` | string | `false` | 'true' / 'false' (usually needs.gate.outputs.prerelease). |
| `artifact-pattern` | string | `release-*` | Artifact name pattern to attach (empty = release without assets). |
| `files` | string | `*` | Globs (relative to the download dir) of files to attach, one per line. |
| `checksums` | boolean | `true` | 生成 SHA256SUMS-<tag>.txt。 |
| `body-path` | string | `''` | Curated notes file ({tag} is substituted, e.g. docs/releases/{tag}.md); used when it exists, else notes are generated. |
| `draft` | boolean | `false` | 创建为草稿。 |

### `pages.yml` — Pages

Jobs：`Build`（每个事件都构建）、`Deploy`（只在 push 默认分支时）。调用方 job 权限：`contents: read`、`pages: write`、`id-token: write`；仓库 Pages 来源设为 GitHub Actions。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `working-directory` | string | `.` | 项目目录（相对仓库根）。 |
| `bun-version` | string | `''` | Bun version (empty = package.json packageManager / .bun-version). |
| `install-command` | string | `bun install --frozen-lockfile` | 安装命令。 |
| `build-command` | string | `bun run docs:build` | 构建命令（node-ci: auto / 显式 / ''）。 |
| `output-dir` | string | `docs/.vitepress/dist` | Build output directory, relative to working-directory. |
| `deploy` | boolean | `true` | Deploy when the run is a push to the default branch. |

### `actionlint.yml` — Workflow lint

Job：`actionlint`（actionlint 内置调用 shellcheck）。

| input | 类型 | 默认 | 说明 |
|---|---|---|---|
| `actionlint-version` | string | `1.7.12` | actionlint release (without the v), downloaded from rhysd/actionlint and checked against its checksums file. |

### `actions/apt-install` — Apt install

Install Debian/Ubuntu packages with retries. Works on hosted runners (sudo) and in root containers (no sudo). No-op when `packages` is empty.

| input | 默认 | 说明 |
|---|---|---|
| `packages` | `''` | Space- or newline-separated package list. |

### `actions/cargo-publish` — Cargo publish

Publish crates to crates.io in the given order, idempotently: a version that is already on the index is skipped, and each crate waits for the index before the next one is published (core -> cli style workspaces). The token only reaches the publish commands.

| input | 默认 | 说明 |
|---|---|---|
| `packages` | **必填** | Crate names in publish order, one per line. |
| `token` | **必填** | crates.io token (secret CARGO_REGISTRY_TOKEN, or the output of rust-lang/crates-io-auth-action). |
| `dry-run` | `false` | 'true' runs cargo publish --dry-run only. |
| `index-wait-attempts` | `40` | How many 15 s polls to wait for each crate to appear on the index. |

### `actions/package-archive` — Package archive

Stage files and create <asset>.tar.gz (or .zip on Windows / when requested) in `out-dir`. Works on Linux, macOS and Windows (Git Bash). Prints the archive path as an output.

| input | 默认 | 说明 |
|---|---|---|
| `asset` | **必填** | Archive base name without extension (e.g. haruki-hmes-v1.2.0-x86_64-unknown-linux-musl). |
| `files` | **必填** | Files or directories to include, one per line. `src=>dest` renames inside the archive. |
| `format` | `auto` | auto (zip on Windows targets, else tar.gz) \| tar.gz \| zip |
| `layout` | `dir` | dir = files under a top-level <asset>/ directory; flat = files at archive root. |
| `windows` | `false` | 'true' when packaging a Windows target (selects zip in auto mode). |
| `out-dir` | `dist` | Output directory. |

outputs: `path`

### `actions/setup-rust` — Setup Rust

Install a Rust toolchain and restore Swatinem/rust-cache. The toolchain comes from the `toolchain` input, else the channel in rust-toolchain(.toml), else stable. The cache is saved only from the default branch (PRs and tags restore, never write).

| input | 默认 | 说明 |
|---|---|---|
| `toolchain` | `''` | Toolchain override (e.g. 1.98.0). Empty = rust-toolchain(.toml) channel, else stable. |
| `components` | `''` | Comma-separated rustup components (e.g. rustfmt,clippy). |
| `targets` | `''` | Comma-separated extra targets (e.g. wasm32-unknown-unknown). |
| `working-directory` | `.` | Directory that holds rust-toolchain(.toml) and the main Cargo project. |
| `cache` | `true` | Restore/save Swatinem/rust-cache. |
| `cache-key` | `''` | rust-cache shared-key. Use one key per job purpose (lint, test, coverage, release-<label>). |
| `cache-workspaces` | `''` | rust-cache workspaces ("dir -> target" per line). Empty = "<working-directory> -> target". |
| `cache-save` | `auto` | 'auto' saves only on the default branch; 'true'/'false' force it. |
| `cache-all-crates` | `false` | Pass-through to rust-cache (keep installed crates such as cargo-llvm-cov). |

outputs: `toolchain`

### `actions/verify-version` — Verify version

Resolve the release version and, on a tag push, fail unless the tag equals <tag-prefix><version declared in the manifest>. The version lives in the manifest (bumped by a PR before tagging); CI never rewrites Cargo.toml/pyproject from the tag.

| input | 默认 | 说明 |
|---|---|---|
| `source` | `cargo` | cargo \| pyproject \| package-json \| file \| none. 'none' takes the version from the tag only. |
| `path` | `''` | Manifest path. Defaults per source (Cargo.toml, pyproject.toml, package.json, VERSION). |
| `extra-paths` | `''` | Additional manifests (same source syntax is auto-detected by file name) that must carry the same version, one per line. |
| `tag-prefix` | `v` | Tag prefix in front of the version (v, engine-v, ...). |

outputs: `version`, `tag`, `is-tag`, `prerelease`

### `actions/wait-for-checks` — Wait for checks

Block until the named check run on a commit has completed, and fail unless it succeeded. Used by release workflows so a tag on a red (or still running) main commit never ships, and so the main-built image already exists when the tag re-tags it. Needs `checks: read` (and `contents: read`).

| input | 默认 | 说明 |
|---|---|---|
| `check-name` | `CI OK` | Check run name to wait for (the aggregate job name in ci.yml). |
| `sha` | `${{ github.sha }}` | Commit to inspect. |
| `timeout-minutes` | `30` | Give up after this many minutes. |
| `token` | `${{ github.token }}` | Token with checks:read. |

## License

MIT，见 [LICENSE](LICENSE)。
