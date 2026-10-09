# AGENTS.md

本仓库的工作说明。模板的用法、约定、版本策略和每个 input 的说明都在 [README.md](README.md)，这里只写改动本仓库时需要知道的事。

## 这是什么

共用的 GitHub Actions 模板：`.github/workflows/` 下 14 个可复用工作流（`on: workflow_call`）加 `actions/` 下 6 个 composite action，外加本仓库自己的 CI `self-test.yml`。各仓库用 `seiunx-dev/ci-templates/.github/workflows/<name>.yml@v1` 调用。

仓库必须保持 **public**：别的 owner 名下的仓库只能调用 public 仓库里的可复用工作流和 action。不要写进任何内部基础设施信息或密钥。

## 布局

| 路径 | 内容 |
|---|---|
| `.github/workflows/*.yml` | 可复用工作流（每个文件开头的注释说明用法），以及 `self-test.yml`（工作流名 `CI`） |
| `actions/<name>/action.yml` | composite action：`setup-rust`、`apt-install`、`verify-version`、`wait-for-checks`、`package-archive`、`cargo-publish` |
| `tools/check_callers.py` | 静态检查：YAML 语法、调用方 inputs/secrets 与声明是否一致、每个 job 有 `timeout-minutes`、第三方 action pin 到完整 SHA；也能检查别的仓库的调用文件 |
| `tests/*_test.{py,sh}` | 从工作流 / action 文件里取出 `run:` 脚本直接运行的单元测试（`sonar.yml` 参数构建、`docker-retag.yml` 顺序保护、`verify-version`），以及 `maturin_test_guard_test.py`（`maturin-wheels.yml` 的 `test` 条件；禁止表达式与裸 `true` / `false` 比较） |
| `tests/fixtures/` | 自测用的最小 Rust / Python / Go / npm / bun / Docker 项目 |
| `CHANGELOG.md` | 每个 `v1.x.y` 一节 |

## 本地检查

和 `self-test.yml` 的 `yaml` job 跑的是同一组命令（需要 PyYAML）：

```sh
python3 tools/check_callers.py
python3 tests/sonar_args_test.py
python3 tests/maturin_test_guard_test.py
bash tests/docker_retag_test.sh
bash tests/verify_version_test.sh
```

actionlint + shellcheck 在 CI 里由 `actionlint.yml` 跑（版本见该文件的 `actionlint-version` 默认值）。各模板在 fixture 上的实际运行只能在 GitHub 上看。

## 改模板时

- **兼容性**：调用方都用 `@v1`，`v1` 移到新版本后立刻对所有仓库生效。新增 input 的默认值必须保持原行为；删除 / 改名 input、改默认行为、改构件名属于不兼容改动，要走 `v2`（见 README“版本策略”）。
- **文档同步**：改了 input / output，要同步 README 的“Inputs 参考”表（它按 `workflow_call` / `action.yml` 声明整理，类型和默认值要与声明一致），必要时还有“目录”表和“约定”一节；发布时在 `CHANGELOG.md` 记一节。
- **每个 job 都写 `timeout-minutes`**，第三方和官方 action 一律 pin 完整 commit SHA 并加 `# vX.Y.Z` 注释（timeout 和 SHA pin 由 `check_callers.py` 检查）。Dependabot（`.github/dependabot.yml`）每周一按组升级这些 pin，提交前缀 `[Chore] `。
- 表达式里**不要和裸 `true` / `false` 比较**：缺省的 matrix key 或对象字段是 null，而 null == false，`x != false` 会把缺省当成 false。用 `toJSON(x) != 'false'` 这类字符串比较（`tests/maturin_test_guard_test.py` 会检查）。
- 可复用工作流内部**不定义 `concurrency`**：被调用时 `github.workflow` 是调用方的名字，会和调用方的 group 撞上。
- 模板内部引用 composite action 用的是 `seiunx-dev/ci-templates/actions/<name>@v1`，所以自测跑不到本次对 `actions/` 的修改，要按 README“发布本仓库”第 3 步先移 `v1` 再手动跑 `CI` 验证。
- **加覆盖**：新行为尽量在 `self-test.yml` 里用 fixture 调一次，或者在 `tests/` 里加脚本测试，并把新 job 加进 `ci-ok` 的 `needs`。自测不跑 `gh-release.yml`、`maturin-wheels.yml`、`go-release.yml` 和 docker 的 promote 路径。

## 提交与发布

- 提交标题：`[Feat]` / `[Fix]` / `[Docs]` / `[Test]` / `[Chore]` 加英文祈使句，例如 `[Fix] Run the locked ruff via uvx in python-uv-ci (#12)`；正文写原因和影响到的调用方。
- 分支名 `feat/…`、`fix/…`、`docs/…`，通过 PR squash 合并到 `main`，合并前等 `CI OK` 变绿。
- 发布：`v1.x.y` 是不可变 annotated tag（仓库 ruleset 禁止更新、删除 `v*.*.*` tag，打错只能发下一个版本），`v1` 是移动 tag，始终指向最新的 `v1.x.y`；每次发布同时创建同名 GitHub Release。具体命令见 README“发布本仓库”。

## Release notes

Release notes follow the org-wide standard [RELEASE_NOTES.md](https://github.com/seiunx-dev/ci-templates/blob/main/RELEASE_NOTES.md) (kept in this repo).

- Title every release with the tag only, e.g. `v1.2.3` (`gh release create v1.2.3 --title v1.2.3 --notes-file <notes>`).
- Write the notes in English. Publish as a pre-release iff the tag has an `-alpha`, `-beta` or `-rc` suffix.
- Omit empty sections; end every item with its PR number `(#123)`, or the short SHA when there is no PR.
- If a release workflow publishes auto-generated notes, rewrite them to the standard afterwards (`gh release edit <tag> --notes-file <notes>`).
