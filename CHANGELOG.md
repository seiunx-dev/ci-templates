# Changelog

本仓库按 [版本策略](README.md#版本策略) 发布：`v1.x.y` 不可变，`v1` 跟随最新的 `v1.x.y`。

## v1.1.13 — 2026-11-08

- 新增 composite action `actions/ci-ok`，用作调用方 `CI OK` 聚合 job 的检查步骤（opt-in，调用方改用之前行为不变；模板工作流本身没有改动）。它保留原来的 needs 判断（needs 里有 `failure` / `cancelled` 就失败），另外通过 jobs API 读本次 run 每个 job 最新一次 attempt 的结论：已结束的 job 有 `failure`、`cancelled`、`timed_out`、`startup_failure` 或 `action_required` 时也失败；`skipped` / `neutral` 视为通过，尚未结束的 job（`CI OK` 自己、`docker-tags`）不看。原因：可复用工作流里的 job 因为没有 runner 接（"The job was not acquired by Runner"）被取消时，调用方 job 的 `needs.<id>.result` 可能仍是 `success`，只看 needs 的 `CI OK` 会在这个 leg 根本没跑的情况下变绿（自测 run 41875681594、41876550379、41882207914 的 macOS leg）。`ignore-jobs` 按 bash 模式放过指定 job（只作用于 run 范围的检查，needs 里的 job 失败一律不放过）。`CI OK` job 需要 `actions: read`（私有仓库必需）；API 调用失败重试 2 次后报错并提示加权限。README 的调用示例和 "唯一的 required check" 约定改用这个 action。新增 `tests/ci_ok_test.sh`。（#25）
- 自测：`CI OK` 改用本 commit 的 `./actions/ci-ok`。（#25）

## v1.1.12 — 2026-11-05

全部是减少 Actions 分钟数的改动（2026-11 审计）。除 `docker.yml` 的 `build-record` 默认值（只影响私有仓库）外，新 input 都是 opt-in、默认行为不变。

- `go-ci.yml`：GOMODCACHE 单独一个缓存条目，只按 go.sum 取 key（`go-mod-<os>-<hash>`），Lint 和 Test 共用，Lint 在精确 key 未命中时保存；默认分支未命中时从空目录开始，不再继承旧 go.sum 的条目。GOCACHE 和 staticcheck 自己的缓存（`os.UserCacheDir()/staticcheck` 或 `STATICCHECK_CACHE`）在保存前裁掉本次没用到的条目（restore 后把条目 mtime 调到两小时前并写标记，保存前删除不比标记新的条目），精确命中（re-run）时不再保存。构建缓存 key 加上调用方工作流文件和 `working-directory`。设了 `coverpkg-exclude` 时合并 `go.out` 里重复的覆盖块（Haruki-Cloud 的构件 26.6 MB），覆盖率数值不变。之前每次 main push 各存一个约 1 GB 的 lint / test 条目，SekaiColo、Toolbox-Backend 的缓存超过 10 GB 配额。各调用方的构建缓存会冷启动一次。新增 `tests/go_cache_test.sh`。（#23）
- `node-ci.yml` 新增 `e2e-needs-check`（默认 `true`；`false` 时 E2E 以 `E2E (parallel)` 和 Check 并行）、`e2e-events`（只在列出的事件上跑 E2E，其余事件 job 级跳过）、`e2e-paths`（E2E job 内按 diff 判断，没有匹配时跳过其余步骤；无法确定比较基准时照跑）、`npm-fetch-timeout` / `npm-fetch-retries`（只在设置时导出 `NPM_CONFIG_FETCH_*`）和 `npm-audit`（默认 `true` 不变；`false` 时模板自带的 `npm ci` 不做安装时 audit）。新增 `tests/node_e2e_paths_test.sh`。（#21）
- `rust-ci.yml` / `python-uv-ci.yml` 新增 `combined`（lint 并进 Test job，Lint job 跳过，私有仓库少一个计费 job）和 `actionlint` / `actionlint-version`（在负责 lint 的 job 里跑 actionlint，校验 checksum；可以去掉单独的 `actionlint.yml` 调用）；`rust-ci.yml` 另有 `debuginfo`（Test job 导出 `CARGO_PROFILE_DEV_DEBUG` / `CARGO_PROFILE_TEST_DEBUG`）。默认值下 job 结构、job 名和 rust-cache key 都不变。（#20）
- `release-gate.yml`：`wait-minutes: 0` 成为有文档的只查一次模式：被打 tag 的 commit 上 "CI OK" 已经成功才放行，否则立刻失败，不再按等待时间计费；用这个模式时要等 "CI OK" 变绿再推 tag（README 约定“Release 不等 CI”）。`actions/wait-for-checks` 在 `timeout-minutes: 0` 时 API 出错最多重试 3 次，并给出明确的提示。`rust-release.yml` 新增 `fail-fast`（默认 `false`，即原来写死的值）。新增 `tests/wait_for_checks_test.sh`。（#22）
- `docker.yml`：`build-record` 默认改为 `${{ !github.event.repository.private }}`：public 仓库照旧上传，私有仓库默认不再上传 `.dockerbuild` 构件（kinagi-api、sekai-backend、HarukiProxy、Haruki-Client release 受影响；没有调用方读取它）；显式值优先。`docker-retag.yml` 新增 `recheck-delay`（默认 10 秒，不变），最后一次写入后不再等待。`sonar.yml` 新增 opt-in 的 `cache`，缓存 scanner CLI 和 `~/.sonar/cache`。`actions/apt-install` 的 apt 调用都带 `Acquire::Retries 5` 和 20 秒 HTTP(S) 超时，新增 `attempt-timeout`（默认 180 秒，`0` 关闭）：卡住的 update / 下载被杀掉重试，解包不受限。新增 `tests/apt_install_test.sh`。（#24）
- 自测：push 触发忽略只改 `**.md` / `LICENSE` 的 commit（PR 和手动触发不过滤）；新增 rust / python `combined`、node e2e 并行变体等调用。（#20、#21、#24）

## v1.1.11 — 2026-10-23

- `node-ci.yml` 新增 `e2e-system-deps`（默认 `always`，行为不变）：`when-missing` 时安装浏览器不带 `--with-deps`，按测试的方式启动一次各浏览器（`e2e-xvfb` 时在 xvfb 下有头启动），只给启动失败的浏览器（以及 chromium / firefox / webkit 以外的名字）跑 `playwright install-deps`。之前浏览器缓存命中时每次仍跑 `install-deps`：hosted runner 已经带了 Chromium 需要的库，apt 只是在装字体，而 Azure 镜像会在这些包上卡住（`Ign:`），Team-Haruki/Haruki-Toolbox 的 E2E job 12 分钟里有 9 分钟花在这一步。自测新增 `node-e2e` fixture，以 `when-missing` 跑 e2e job，系统依赖步骤约 2 秒。（#17）
- e2e job 在任何 Playwright apt 之前写入 apt 配置：`Acquire::Retries 5`、HTTP(S) 超时 20 秒，镜像卡住时尽快换源重试，不再每个包等到默认超时；`e2e-system-deps` 不是这两个值时报错。（#17）
- e2e job 改用项目自己的 `@playwright/test` CLI（`cli.js`），不再用 `npx playwright`，避免 npx 临时下载未锁定版本的包（Sonar `githubactions:S6505` / `S8543`）。（#17）

## v1.1.10 — 2026-10-13

- `actions/setup-rust`：`dtolnay/rust-toolchain` 的 pin 从 02cb101 升到 e2a55d2（上游 master，也是上游 `v1`）。上游改动：`toolchain` / `targets` / `components` 改为经 env 传入并加引号，不再直接插进 `run:` 行（dtolnay/rust-toolchain#187）；`rustup toolchain install` 遇到发布服务器正在更新导致的 checksum 失败时最多重试 4 次（dtolnay/rust-toolchain#186）。setup-rust 传入的三个 input 行为不变，调用方无需改动。（#14）

## v1.1.9 — 2026-10-09

- `maturin-wheels.yml`：没写 `test` 的 target 现在会跑冒烟测试和 `test-command`。之前的条件是 `matrix.t.test != false`，而缺省的 key 是 null，GitHub 表达式里 null 和 false 比较相等（都转成 0），所以只有显式写了 `"test": true` 的 target 才测试，与文件头"false to skip"的约定相反（Team-Haruki/pjsekai-scores-rs 发现）。改为 `toJSON(matrix.t.test) != 'false'`，只有 `"test": false` 跳过。影响：seiunx-dev/cridecoder、seiunx-dev/unity-rs 的 wheel job 从这一版起真正安装并导入 wheel（unity-rs 还会跑 `test-command`）；显式写 `true` / `false` 的调用方不变。
- 新增 `tests/maturin_test_guard_test.py`：检查两个步骤用的是这个条件、自测的 `maturin-test-guard` job 用的是同一个表达式，并禁止任何工作流 / action 的表达式与裸 `true` / `false` 比较。自测新增 `maturin-test-guard` job，在 GitHub 上对 `test` 缺省 / false / true 三种 target 实际求值。

## v1.1.8 — 2026-10-01

- `rust-ci.yml` 新增 `lint`（默认 `true`，行为不变）：`false` 时不跑 lint job（fmt、clippy、`extra-lint-command`），只跑测试。用于在其他 OS 上额外调用一次、代码已由主调用 lint 过的情况：seiunx-dev/unity-rs 原来在 Windows / macOS 上只跑 build + test，迁移后多出的 Windows clippy 会因为只在 Windows 下编译的代码报 pedantic lint 而失败，也多花一份 runner 时间。自测的 macOS 调用改为 `lint: false`。

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
