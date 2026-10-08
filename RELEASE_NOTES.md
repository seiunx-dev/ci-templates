# Release notes standard

This standard applies to every repository under seiunx-dev, Team-Haruki and MejiroRina that publishes releases.

## Rules

1. **Language and voice:** English only. Write present-tense sentences that start with a verb, from the user's point of view rather than the implementation's. Write "Skip charts that have no music metas", not "Add metas index filter".
2. **Title:** exactly the tag, for example `v3.8.3`.
3. **Release type:**
   - Tags with an `-alpha`, `-beta` or `-rc` suffix are published as **pre-releases**.
   - All other tags are regular releases.
   - Every tag must have a release.
4. **Empty sections:** omit any section that would be empty. A fix-only release has just the summary, **Fixed** and the **Full Changelog** link.
5. **Mapping commit prefixes to sections:**

   | Prefix | Section |
   | --- | --- |
   | `[Feat]` | Added |
   | `[Fix]` | Fixed |
   | `[Perf]` | Performance |
   | `[Chore]`, `[CI]`, `[Docs]`, dependency bumps | collapsed **Maintenance** |

   If a maintenance change is user-visible (a new minimum runtime or toolchain version, a changed default, a removed flag), move it to **Changed** or **Upgrade notes** instead.
6. **Sources:**
   - End every item with its PR number `(#123)`. Use the short commit SHA when there is no PR.
   - Credit external contributors with `by @user` after the item. Don't credit the maintainers.
7. **Breaking changes:** they come first and always say what to do. Link migration notes when they exist.
8. **Public repositories:** do not mention internal infrastructure, such as node or server names, private or tailnet IPs, internal hostnames or server paths.
9. **Reconstructed notes:** a release created afterwards for a tag that never had one ends with `_Release notes reconstructed on <YYYY-MM-DD>._`.

## Template

````markdown
One to three sentences on what this release is for and who should upgrade.

## ⚠️ Breaking changes
- What changed, who is affected, and what to do. Link migration notes. (#PR)

## Added
- New capability, described from the user's side. (#PR)

## Changed
- Behaviour change that is not breaking. (#PR)

## Fixed
- What was wrong and in which situation it happened. (#PR)

## Performance
- What got faster or smaller, with a number when there is one. (#PR)

## Security
- Advisory ID, affected component, and whether our usage was exposed. (#PR)

## Upgrade notes
- New or renamed config keys and env vars, with their defaults.
- Database or schema migrations, and whether they run automatically.
- Minimum versions (toolchain, runtime, dependencies) and compatibility with other services.

## Artifacts
- Docker: `ghcr.io/<owner>/<image>:<version>`
- Binaries and packages: attached below, with checksums in `SHA256SUMS-<tag>.txt`.

<details>
<summary>Maintenance</summary>

- Dependency, CI and documentation changes, one line each. (#PR)

</details>

**Full Changelog**: https://github.com/<owner>/<repo>/compare/<previous-tag>...<tag>
````

For the first release of a repository, replace the compare link with `**Full Changelog**: https://github.com/<owner>/<repo>/commits/<tag>`.

## Example

```markdown
Fixes failed lives for accounts whose song pool includes charts without music metas. Recommended for all nodes.

## Fixed
- Skip charts that have no music meta when scoring through deck-service. Random, playlist, mission and miner picks no longer choose them, and a fixed song without metas is refused before stamina is spent, with a hint to switch to SUS scoring. The index refreshes every 30 s, so charts become eligible again as soon as upstream metas include them. (#127)

## Artifacts
- Docker: `ghcr.io/mejirorina/sekaicolo:4.5.26`

**Full Changelog**: https://github.com/MejiroRina/SekaiColo/compare/v4.5.25...v4.5.26
```
