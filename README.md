# commandbox-release

![commandbox-release logo](https://raw.githubusercontent.com/homestar9/commandbox-release/refs/heads/master/commandbox-release-logo.avif)

`commandbox-release` builds and publishes CFML modules and web apps. It adds `box release`
commands to [CommandBox](https://www.ortussolutions.com/products/commandbox).

The commands can change your project's version, add a version and date to its release notes,
run TestBox tests, and build a zip file. They publish to GitHub, ForgeBox, or both. Each project
keeps its settings in `release.json` in the project's root folder.

## What you need

Install [CommandBox](https://www.ortussolutions.com/products/commandbox) and
[Git](https://git-scm.com/). Run the examples below in your terminal.

Your project needs a Git repository with a remote named `origin`. This is the repository that
release commands get commits from and push commits and tags to. For GitHub releases, `origin`
must point to the project's GitHub repository.

You will choose where to publish and whether to run tests during setup:

- To publish to GitHub, install [GitHub CLI](https://cli.github.com/) and sign in with
  `gh auth login`.
- To publish to ForgeBox, use a ForgeBox account and sign in with `box forgebox login`.
- To run tests, provide the URL of your project's TestBox runner. Start the test server before
  releasing, or configure the module to start servers for you under [Test more than one CFML
  engine](#test-more-than-one-cfml-engine). A CFML engine, such as Lucee or Adobe ColdFusion,
  runs your CFML code.

## Install

```bash
box install commandbox-release
```

Update it later with:

```bash
box update commandbox-release --system
```

## Set up a project

Go to the project's root folder and run:

```bash
box release init
```

Answer the questions about publishing and tests. If the project has no `box.json`, setup
offers to create it. That file describes your package and stores its version.

Setup creates `release.json` and creates `CHANGELOG.md` if needed. It also updates two files:

- `box.json`: adds file patterns to the `ignore` list to keep development files out of the package.
- `.gitignore`: adds `.tmp/` and `.artifacts/` so Git ignores the generated build files.

Open `release.json` and check these settings before releasing:

- `branch`: your production branch, usually `main` or `master`. This is the branch you publish
  from. In a Gitflow project, use the production branch rather than `develop`.
- `publish.github` and `publish.forgebox`: where to publish. Sign in to each service you enable.
- `runTests` and `testRunner`: whether to run tests and the URL of the test runner. Use
  `runTests: false` when another system already runs your tests.

Modules publish to GitHub and ForgeBox by default. Web apps publish to GitHub by default.
Setup treats a project as a module when `box.json` has a module type, such as `modules` or
`commandbox-modules`, or the project has `ModuleConfig.cfc` in its root folder.

Review the `box.json` ignore list too. It controls which files go into the package.
The [settings reference](#settings) below explains the options.

Optional setup flags:

- `--yes` accepts the default answers without asking questions.
- `--docs` copies the release guide to `RELEASE.md` in your project.
- `--ci` copies a GitHub Actions workflow to `.github/workflows/release.yml`. That workflow
  publishes when you push a version tag. Use it instead of publishing from your computer.

You can run setup again. It keeps existing files unless you use `--force`.

## Publish your first release

These steps publish directly from your production branch. If your project uses release
branches, follow [Gitflow releases](#gitflow-releases) instead.

1. Switch to the branch set in `release.json`. For example, if `branch` is `main`:

   ```bash
   git switch main
   ```

2. Add notes under `## [Unreleased]` in `CHANGELOG.md`. Describe what changed. For example:

   ```markdown
   ## [Unreleased]

   ### Added

   - A search form on the home page.
   ```

3. Commit the setup files and notes before publishing:

   ```bash
   git add box.json release.json CHANGELOG.md .gitignore
   git commit -m "Set up releases and add release notes"
   ```

   Commit any other changes you want in this release too. A real release stops if you have
   uncommitted changes.

4. Start the test server if your settings require one. Then check the release with a dry run:

   ```bash
   box release publish patch --dryRun
   ```

   This runs enabled tests and builds and checks the zip. It writes build files to `.tmp/`
   and `.artifacts/` by default. It does not change the version in `box.json`, edit your
   changelog, commit, publish, or push. Read the output and fix any reported problems.

5. Publish after the dry run passes:

   ```bash
   box release publish patch
   ```

   `patch` changes a version such as `1.0.0` to `1.0.1`. The command moves your release notes
   into a dated section and commits the version and changelog changes. It runs enabled tests
   again and builds the package before publishing to the services you chose.

If you want to keep the version already in `box.json` for your first release, use `none`
instead of `patch` in both commands. It dates and commits the release notes without changing
the version.

If publishing stops, follow the recovery steps in the output. If the version change was
committed but nothing was published or pushed, fix the problem and run `box release publish`
without a level. This uses the current version rather than changing it again.

## Ways to release

### Change the version and publish in one command

```bash
box release publish patch              # 1.0.0 -> 1.0.1 for a bug fix
box release publish minor              # 1.0.0 -> 1.1.0 for a new feature
box release publish major              # 1.0.0 -> 2.0.0 for a breaking change
box release publish minor beta         # 1.0.0 -> 1.1.0-beta.1 for an early version to test
```

Run these commands on your production branch, such as `main`. The command first checks Git,
the changelog, and your service sign-ins. Then it updates the branch from `origin`, changes the
version, and moves the `[Unreleased]` notes into a dated section. It commits the changes as
`Release 1.0.1`, runs the tests, and builds and checks the zip. It publishes only after those
steps pass. When GitHub publishing is enabled, it creates a version tag, pushes the branch
and tag, and creates the GitHub Release. A tag marks the commit used for a version.

Use `minor beta` to start a prerelease: a version for testing before the normal release.
If the command stops, follow its recovery instructions. Do not repeat a command with a level
after its version change has been committed.

### Change the version and publish in separate steps

```bash
box release bump patch                 # change the version and date the release notes
git add box.json CHANGELOG.md
git commit -m "Release 1.0.1"
box release check                      # optional
box release publish --dryRun           # optional practice
box release publish                    # test, build, and publish the current version
```

`box release publish` without a level uses the version already in `box.json`. It does not
change that version.

## Gitflow releases

Gitflow uses `develop` for completed work, temporary branches to prepare releases or hotfixes,
and a production branch for published versions. A hotfix is a fix made from production.
Set `branch` in `release.json` to the production branch.

### Merge and publish in one command

On `develop`, include a version level to create a release branch and publish its changes:

```bash
box release gitflow minor --dryRun     # show the steps and build from the current branch
box release gitflow minor              # from 1.0.0: create release/1.1.0, merge, and publish
```

On an existing release branch, use `box release gitflow` without a level if the version in
`box.json` is already newer than production. Otherwise, include a level, such as
`box release gitflow minor`.

The command:

1. Checks Git, release notes, and service sign-ins.
2. Gets commits from `origin` and updates local branches when `gitSync` is enabled. If the
   current branch changes, it stops so you can run it again to check the updated files.
3. Creates a release branch if you started on `develop`.
4. Updates the version and dates the `[Unreleased]` notes when a level is used. It commits
   those files with a message such as `Release 1.1.0`.
5. Runs enabled tests on the release branch.
6. Merges into `develop` and the production branch.
7. Builds and publishes from production using your settings. It runs tests again if production
   has different files from the tested release branch.
8. Pushes both branches, switches to `develop`, and deletes the release branch locally and
   on `origin`. Use `--keepBranch` to keep the release branch.

Nothing is pushed until the build passes. If the command stops before publishing or creating
a tag, follow the reported steps. Fix any code changes on the release branch and commit them.
Then run `box release gitflow` on that branch without a level. Git does not repeat merges that
are already complete. If publishing or pushing has started, use the printed recovery steps.

For a hotfix, create a `hotfix/*` branch from production and commit your fix first. Run
`box release gitflow` on that branch. The command uses the version in `box.json` if it is newer
than production. Otherwise, it makes a patch version. It merges into both `develop` and
production. If a release branch is also open, use `box release gitflow --keepBranch` to keep
the hotfix branch. After publishing, merge the hotfix branch into the release branch yourself.
If the hotfix branch was already deleted, merge the production branch into the release branch
to include the fix.

A Gitflow dry run builds from your current branch. It does not create or merge branches,
change `box.json` or the changelog, publish, or push. Its zip does not include the results of
the planned merges.

Branch names come from your Gitflow settings in Git config. GitKraken and `git flow` store
them there. The defaults are `develop`, `release/`, and `hotfix/`. The production branch comes
from `release.json` and must match your Gitflow settings when those settings specify it.

### Gitflow and GitKraken

You can use GitKraken to merge the release branch and create its version tag. In this example,
production is `master`, and the current version is `1.0.0`:

```text
start a release in GitKraken           # develop -> release/1.0.1
(add notes under [Unreleased])
box release bump patch                 # works on any branch; no commit
commit "Release 1.0.1" in GitKraken
finish the release in GitKraken        # merges into master and develop; creates v1.0.1
check out master in GitKraken
box release publish                    # uses v1.0.1 and pushes the tag if needed
```

For a hotfix, use a `hotfix/*` branch in the same way. `box release publish patch` stops on
`release/*` and `hotfix/*` branches and shows both release options. The
[release guide](templates/RELEASE.md) also explains the `git-flow` command and pull requests.

## Commands

Run these commands from any folder inside a project. `box release help` prints the same list.

| Command | What it does |
| --- | --- |
| `box release init` | Creates the release settings, changelog, and package ignore list. |
| `box release publish` | Publishes the version in `box.json`. Uses an existing tag if it points to the current commit. |
| `box release publish patch` | Changes the version, commits the change, and publishes. You can also use `minor`, `major`, or a prerelease level. |
| `box release publish --dryRun` | Builds the zip without committing, publishing, or pushing. |
| `box release publish --skipTests` | Publishes without running the tests again. |
| `box release gitflow minor` | On `develop`, creates a release branch, merges it, and publishes. On a release or hotfix branch, changes the version, merges that branch, and publishes. |
| `box release gitflow` | Merges and publishes the current release or hotfix branch. Uses its version if newer than production; otherwise, a hotfix uses `patch`, and a release requires a level. |
| `box release bump patch` | Changes the version and dates the release notes. It does not commit. |
| `box release check` | Finds problems that would stop a release. |
| `box release test` | Runs the tests once, or on each engine listed in `release.json`. |
| `box release package` | Builds and checks the zip file without publishing. |
| `box release notes` | Shows the release notes for the current version. |
| `box release resume` | Finishes a release that stopped after publishing. |

Run `box help release publish` to see all help for one command.

## Settings

The setup command creates `release.json` in the project root. Edit that file to change how
release commands work. This example publishes to both GitHub and ForgeBox and runs tests:

```json
{
    "requires": "3.0.0",
    "branch": "main",
    "changelog": "CHANGELOG.md",
    "testRunner": "http://127.0.0.1:60299/tests/runner.cfm",
    "runTests": true,
    "publish": {
        "forgebox": true,
        "github": true
    },
    "engines": []
}
```

The JSON examples below show individual settings. Update those values in your existing
`release.json`; keep the other settings you need.

### Choose the production branch

Set `branch` to the production branch, usually `main` or `master`. This branch holds published
versions and their tags. In a Gitflow project, do not set it to `develop` or a temporary
`release/*` branch. Setup uses Gitflow's production branch when it finds one. Check the value
in the new file before your first release.

### Publish to GitHub but not ForgeBox

```json
{
    "publish": {
        "forgebox": false,
        "github": true
    }
}
```

If `release.json` does not set `publish.forgebox`, modules publish to ForgeBox and other
projects do not. Set it to `true` or `false` to choose for yourself.

### Do not run tests during the build

Use this setting when another system runs the tests, such as a continuous integration (CI)
workflow:

```json
{
    "runTests": false
}
```

### Keep files out of the package

The package includes project files unless a pattern in the `box.json` `ignore` list leaves
them out. A pattern is a rule that matches file paths. ForgeBox uses the same list, so both
packages exclude the same files. Setup adds common patterns. You can edit the list at any time.

```json
{
    "ignore": [
        "**/.*",
        "/tests/",
        "/test-harness/",
        "/server*.json",
        "**/*.bak"
    ]
}
```

Here is how the patterns match paths:

- `/tests/` starts with a slash, so it matches only the `tests` folder in the project root.
- `temp/` has no leading slash, so it matches a folder named `temp` at every depth.
- `**/*.bak` matches every `.bak` file at every depth.
- `!/.htaccess` keeps a file that an earlier pattern removed. Web apps use this to include
  `.htaccess` and `.well-known/` while `**/.*` removes the other hidden files.

The package also leaves out `.git`, `.gitignore`, `release.json`, `.tmp`, and `.artifacts`.
The build does not use `.gitignore` to choose package files. For example, `.gitignore` may
exclude a `modules/` folder that the running project needs. The build stops if the `box.json`
ignore list excludes `box.json`, or `ModuleConfig.cfc` when the project has one.

### Test more than one CFML engine

During setup, the command finds `server.json` and `server-*.json` files in the project root.
It adds each server to `engines` in filename order. Remove servers you do not want to test.

```json
{
    "engines": [
        { "name": "Lucee 5", "configFile": "server-lucee@5.json" },
        { "name": "Adobe 2023", "configFile": "server-adobe@2023.json" }
    ]
}
```

`box release test` starts each engine, runs the tests, and stops the engine before starting
the next one. It tries every engine even if one fails. It reports an error at the end if any
engine failed.

When tests fail, the command lists each failed test as `bundle > suite > spec -- message`.
Here, a bundle is a test file, a suite is a group of tests, and a spec is one test.
When testing several engines, the final results group failed tests by engine.

### Stop the tests at the first failure

The release commands use TestBox's `eagerFailure` option to ask the runner to stop after the
first test file that has a failure. The rest of that file still runs. Later files are skipped.

The standard TestBox runner ignores this option and always runs every test. To use it, copy
`testbox/system/runners/HTMLRunner.cfm` into your `tests` folder, include the copy from
`tests/runner.cfm`, and change two lines in the copy:

```cfml
<!--- Add next to the other cfparam tags --->
<cfparam name="url.eagerFailure" default="false" type="boolean">

<!--- Pass the option to TestBox --->
results = testbox.run( reporter=url.reporter, eagerFailure=url.eagerFailure )
```

A custom runner that calls `testbox.run()` itself needs only the `eagerFailure` argument. Other
tools that call the runner without `eagerFailure=true` still run every test.

### Other settings

| Setting | Default | What it does |
| --- | --- | --- |
| `requires` | the version that created the file | The oldest commandbox-release version this project can use. Commands stop and show how to update if your installed version is too old. |
| `tagPrefix` | `v` | The text before the version in tag names. |
| `gitSync` | `true` | Gets new commits from `origin` before a release, without making a merge commit. |
| `requireCleanTree` | `true` | Stops a release when there are uncommitted changes. |
| `stagingDir` | `.tmp` | The temporary build folder. |
| `artifactsDir` | `.artifacts` | Where the zip and checksum files are written. |
| `coldboxMapping` | `test-harness/coldbox` | The folder used for the `coldbox` mapping during the build, if the folder exists. |
| `warmup` | `{ "attempts": 60, "delaySeconds": 5 }` | How often `release test` checks whether each engine is ready. |

## Common problems

| Message | How to fix it |
| --- | --- |
| `Command "release" cannot be resolved` | Install the module in this CommandBox with `box install commandbox-release`. |
| `No box.json file was found` | Run the command from inside a CommandBox project, or run `box release init` to create one. |
| `This project requires commandbox-release X or newer` | Run `box update commandbox-release --system`. |
| `You have uncommitted changes` | Commit or stash the changes, and then run the command again. |
| `You are on a Gitflow release branch` | Run `box release gitflow` on that branch if its version is newer than production. Otherwise, include a level, such as `box release gitflow patch`. See [Gitflow releases](#gitflow-releases) for the GitKraken option. |
| `... could not be merged into develop` | Switch to `develop`, merge the release or hotfix branch, fix the conflicts, and commit. Switch back to the release or hotfix branch and run `box release gitflow` without a level. |
| `The test server ... did not answer` | Start the project's test server. You can also correct `testRunner` or set `runTests` to `false` when tests run somewhere else. |
| `Could not find the GitHub CLI` | Install `gh`, open a new terminal, and run `gh auth login`. |
| `The "## [Unreleased]" section ... is empty` | Add notes under `[Unreleased]`, and then run the command again. |
| `The package is missing box.json` or `ModuleConfig.cfc` | Remove the `box.json` ignore pattern that excludes the required file. |
| `Tag v1.2.3 already exists on origin` | That version was already released. Change the version before trying again. |
| `Tag v1.2.3 points to a different commit on origin` | The local and remote tags point to different commits. Do not move the published tag. Check the release history or use a new version. |
| `Version X is committed locally and nothing was published` | Fix the problem in the message. Then run `box release publish` without a level. |
| `release.json contains invalid JSON` | Check for missing quotes, extra commas, or backslashes that must be doubled. |

Run `box release check` when you do not know what is wrong. It reports release problems
without changing the project.

## Develop commandbox-release

Install the development dependencies and run the tests:

```bash
box install
box run-script test
```

The test runner loads this working copy as the `commandbox-release` module. It uses a separate
CommandBox installation, so a globally installed version does not affect the tests. Unit
tests check version rules, changelogs, settings, project lookup, and ignore patterns.
Integration tests create temporary projects in `.test-work/`. They run real commands through
`tests/support/Invoke.cfc` and use a local Git remote. They do not publish to ForgeBox or
GitHub.

To test the working copy as an installed module, run `box install <path to this checkout>`.
Then open a new shell. `box release help` should list the commands. The module uses its own
`box release publish` command to release itself.

Files in `commands/release/` receive command arguments. Files in `models/` do the release
work. Rules that do not need CommandBox have their own model components.

## More information

- [Detailed release guide](templates/RELEASE.md)
- [Optional GitHub Actions workflow](templates/github-release.yml). It publishes when you push a
  version tag. If you use it, do not also run `box release publish` on your computer. Run
  `box release bump`, commit, and push the tag instead.
- [Changelog](CHANGELOG.md)
- [MIT License](LICENSE)
