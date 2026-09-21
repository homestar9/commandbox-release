# commandbox-release

![commandbox-release logo](https://raw.githubusercontent.com/homestar9/commandbox-release/refs/heads/master/commandbox-release-logo.avif)

`commandbox-release` is a [CommandBox](https://www.ortussolutions.com/products/commandbox)
module that adds `release` commands: a small command-line tool for releasing CFML projects.
Install it once on your computer. In any project it can:

- change the version and date the changelog;
- run TestBox tests;
- build and check a release zip file; and
- publish a package to ForgeBox and GitHub.

It works for two kinds of project:

- **Modules** (ColdBox modules, CommandBox modules, and other ForgeBox packages) publish to
  ForgeBox and get a GitHub Release.
- **Web apps** get a GitHub Release with a versioned zip file and do not use ForgeBox.

You choose during setup. Each project keeps its release settings in one small `release.json`
file.

## Before you install

Every computer needs:

- [CommandBox](https://www.ortussolutions.com/products/commandbox)
- [Git](https://git-scm.com/)

Your project settings may also require:

- [GitHub CLI](https://cli.github.com/) to create GitHub Releases;
- a ForgeBox account to publish to ForgeBox; and
- a running test server when `runTests` is `true`.

Sign in to each service that you use:

```bash
gh auth login
box forgebox login
```

## Install

```bash
box install commandbox-release
```

Update it later with:

```bash
box update commandbox-release --system
```

A project can require a version through `requires` in `release.json`. Release commands stop
and show the update command when the installed module is too old.

## Set up a project

Go to the project's root folder and run:

```bash
box release init
```

The command asks whether the project is a module or a web app, whether to publish to ForgeBox
and GitHub, and whether to run the tests before every release. It then:

- creates `release.json` with your answers and settings found in the project;
- creates `CHANGELOG.md` when the project does not already have one;
- adds the recommended patterns to the `ignore` list in `box.json`, which keeps tests, server
  files, and editor files out of the package; and
- adds its `.tmp/` and `.artifacts/` build folders to `.gitignore`.

Use `--yes` to accept every default without questions, and `type=module` or `type=app` to
skip the first question. Use `--docs` to copy the detailed `RELEASE.md` guide into the project.
Use `--ci` to copy a GitHub Actions workflow to `.github/workflows/release.yml`. You can safely
run the command again. It keeps existing files unless you use `--force`.

If the folder has no `box.json` yet, the command offers to create one.

## Release a ColdBox module

```bash
box release init                       # once: answer "module"
(add notes under [Unreleased] in CHANGELOG.md)
box release publish patch --dryRun     # practice: nothing is written, published, or pushed
box release publish patch              # bump, commit, check, test, build, ForgeBox, tag, GitHub Release
```

## Release a web app

```bash
box release init                       # once: answer "app"
(add notes under [Unreleased] in CHANGELOG.md)
box release publish patch --dryRun
box release publish patch              # bump, commit, check, test, build zip, tag, GitHub Release
```

The only difference is the answer during setup. A web app skips ForgeBox and attaches the zip
file to the GitHub Release.

## Three ways to release

### Fast: one command from the production branch

```bash
box release publish patch              # 1.0.0 -> 1.0.1 for a bug fix
box release publish minor              # 1.0.0 -> 1.1.0 for a new feature
box release publish major              # 1.0.0 -> 2.0.0 for a breaking change
box release publish minor beta         # 1.0.0 -> 1.1.0-beta.1 to start a prerelease
```

The command checks Git, the changelog, and the sign-ins first. It then updates the branch from
origin, changes the version, moves the `[Unreleased]` notes into a dated section, commits
`Release 1.0.1`, runs the tests, builds and checks the zip, publishes, tags, pushes, and
creates the GitHub Release. Nothing is published, tagged, or pushed until every check passes.

If a step fails after the commit, the message says so. The version is committed on your
computer, so after the fix you run `box release publish` without a level.

### Granular: bump first, publish later

```bash
box release bump patch                 # box.json 1.0.0 -> 1.0.1 and dated changelog; no commit
git add box.json CHANGELOG.md
git commit -m "Release 1.0.1"
box release check                      # optional
box release publish --dryRun           # optional practice
box release publish                    # check, test, build, publish, tag, GitHub Release
```

`box release publish` without a level never changes the version. It publishes whatever version
`box.json` contains.

### Gitflow and GitKraken

Gitflow creates the version tag when a release is finished, so the version is changed on the
release branch and the tool only publishes:

```text
start a release in GitKraken           # develop -> release/1.0.1
(add notes under [Unreleased])
box release bump patch                 # works on any branch; no commit
commit "Release 1.0.1" in GitKraken
finish the release in GitKraken        # merges to master, creates tag v1.0.1, back-merges develop
check out master in GitKraken
box release publish                    # finds v1.0.1 at the current commit and pushes it if needed
```

Hotfixes work the same way on a `hotfix/*` branch. `box release publish patch` refuses to
run on a `release/*` or `hotfix/*` branch and prints these steps instead. The
[detailed release guide](templates/RELEASE.md) covers the `git-flow` extension and pull
request workflows too.

## Commands

Run these commands from any folder inside a project. `box release help` prints the same list.

| Command | What it does |
| --- | --- |
| `box release init` | Sets up a project: `release.json`, `CHANGELOG.md`, and the `box.json` ignore list. |
| `box release publish` | Publishes the version in `box.json`. Uses a tag that already points to the commit. |
| `box release publish patch` | Bumps, commits, and publishes. Also `minor`, `major`, `prerelease`, or `minor beta` for a prerelease. |
| `box release publish --dryRun` | Practices either form without writing, publishing, or pushing. |
| `box release publish --skipTests` | Publishes without running the tests again. |
| `box release bump patch` | Changes the version and dates the notes without committing. |
| `box release check` | Finds problems that would stop a release. |
| `box release test` | Runs the tests once, or on each engine listed in `release.json`. |
| `box release package` | Builds and checks the zip file without publishing. |
| `box release notes` | Shows the release notes for the current version. |
| `box release resume` | Finishes a release that stopped after publishing. |

Run `box help release publish` to see all help for one command.

## Settings

Edit `release.json` in the project root to control the release commands. The setup command
creates this file.

```json
{
    "requires": "3.0.0",
    "projectType": "module",
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

### Choose the production branch

`branch` is the branch that receives release tags and published versions. This is usually
`main` or `master`. For Gitflow projects, use the production branch. Do not use `develop` or a
temporary `release/*` branch. The setup command uses Gitflow's configured production branch
when it can find one. Always check the generated value.

### Publish to GitHub but not ForgeBox

```json
{
    "projectType": "app",
    "publish": {
        "forgebox": false,
        "github": true
    }
}
```

An `app` project disables ForgeBox by default. Set `publish.forgebox` to `true` to publish an
app to ForgeBox anyway.

### Do not run tests during the build

Use this setting when another system, such as CI, runs the tests:

```json
{
    "runTests": false
}
```

### Keep files out of the package

The package contains every file in the project except the ones matched by the `ignore` list in
`box.json`. This is the same list that ForgeBox uses, so the zip attached to the GitHub Release
and the package on ForgeBox contain the same files. The setup command adds the recommended
patterns. Edit the list in `box.json` at any time.

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

The patterns use the same syntax as `.gitignore`:

- `/tests/` starts with a slash, so it matches only the `tests` folder in the project root.
- `temp/` has no leading slash, so it matches a folder named `temp` at every depth.
- `**/*.bak` matches every `.bak` file at every depth.
- `!/.htaccess` keeps a file that an earlier pattern removed. Web apps use this to ship
  `.htaccess` and `.well-known/` while `**/.*` removes the other hidden files.

The tool always leaves out `.git`, `.gitignore`, `release.json`, and its own `.tmp` and
`.artifacts` folders. It never uses `.gitignore` as an exclusion list, because a `.gitignore`
rule such as `modules/` would remove files that a module needs at runtime. The build stops
when the ignore list removes `box.json` or a module's `ModuleConfig.cfc`.

### Test more than one CFML engine

During setup, the command finds `server.json` and each `server-*.json` file in the project
root. It adds the files to `engines` in filename order. Review the list and remove servers that
are not part of your compatibility tests.

```json
{
    "engines": [
        { "name": "Lucee 5", "configFile": "server-lucee@5.json" },
        { "name": "Adobe 2023", "configFile": "server-adobe@2023.json" }
    ]
}
```

`box release test` then starts each engine in turn, runs the tests, and stops it. A failure
does not stop the remaining engines. The command returns an error when one or more engines
fail.

### Other settings

| Setting | Default | What it does |
| --- | --- | --- |
| `requires` | the version that created the file | The lowest commandbox-release version allowed to release this project. |
| `tagPrefix` | `v` | The text before the version in tag names. |
| `gitSync` | `true` | Fast-forwards the production branch from origin before a release. |
| `requireCleanTree` | `true` | Stops a release when there are uncommitted changes. |
| `stagingDir` | `.tmp` | The temporary build folder. |
| `artifactsDir` | `.artifacts` | Where the zip and checksum files are written. |
| `coldboxMapping` | `test-harness/coldbox` | A folder that gets a `coldbox` mapping during the build, when it exists. |
| `warmup` | `{ "attempts": 60, "delaySeconds": 5 }` | How long `release test` waits for each engine to answer. |

## Common problems

| Message | How to fix it |
| --- | --- |
| `Command "release" cannot be resolved` | Install the module in this CommandBox with `box install commandbox-release`. |
| `No box.json file was found` | Run the command from inside a CommandBox project, or run `box release init` to create one. |
| `This project requires commandbox-release X or newer` | Run `box update commandbox-release --system`. |
| `This project has build.json from build-template 1.x or 2.x` | See [Upgrading from 1.x or 2.x](#upgrading-from-1x-or-2x). |
| `You have uncommitted changes` | Commit or stash the changes, and then run the command again. |
| `You are on a Gitflow release branch` | Run `box release bump`, commit, finish the release, and publish from the production branch. |
| `The test server ... did not answer` | Start the project's test server. You can also correct `testRunner` or set `runTests` to `false` when tests run somewhere else. |
| `Could not find the GitHub CLI` | Install `gh`, open a new terminal, and run `gh auth login`. |
| `The "## [Unreleased]" section ... is empty` | Add notes under `[Unreleased]`, and then run the command again. |
| `The package is missing box.json` or `ModuleConfig.cfc` | A pattern in the `box.json` ignore list matches a required file. Fix the list. |
| `Tag v1.2.3 already exists on origin` | That version was already released. Change the version before trying again. |
| `Tag v1.2.3 points to a different commit on origin` | The local and remote tags point to different commits. Do not move the published tag. Check the release history or use a new version. |
| `Version X is committed locally and nothing was published` | Fix the reported problem, and then run `box release publish` without a level. |
| `release.json contains invalid JSON` | Check for missing quotes, extra commas, or backslashes that must be doubled. |

Run `box release check` when you do not know what is wrong. It reports release problems
without changing the project.

## Upgrading from 1.x or 2.x

Version 3.0 renamed the module from `build-template` to `commandbox-release`. It reads
`release.json` instead of `build.json`, and it no longer has its own exclusion list. Nothing is
converted automatically, so do these steps in each project:

1. Replace the module:

   ```bash
   box uninstall build-template --system
   box install commandbox-release
   ```

2. Delete the copied `build/` folder if the project still has one from 1.x.
3. Delete `build.json` (or `build/build.json`) and run `box release init`. Copy any custom
   values, such as `branch`, `engines`, or `tagPrefix`, from the old file into the new
   `release.json`. `minimumKitVersion` is now `requires`.
4. Move any custom `excludes` or `excludesAdd` rule into the `ignore` list in `box.json` as a
   glob. Start it with `/` to match only the project root; without `/` it matches at every
   depth. The setup command already added the recommended patterns.
5. Update scripts and CI steps: `release run` is now `release publish`,
   `release run --existingTag` is now just `release publish`, `release engines` is now
   `release test`, and `release github` is now `release resume`. `release migrate` is gone.

## Develop commandbox-release

Install the development dependencies and run the tests:

```bash
box install
box run-script test
```

The test runner loads this checkout as the `commandbox-release` module in its own CommandBox.
The tests use the working copy even when another version is installed globally. Unit tests
cover version rules, changelog handling, settings, project detection, and ignore patterns.
Integration tests create temporary projects under the ignored `.test-work/` folder. They run
the real commands through `tests/support/Invoke.cfc` and use a local Git remote. The tests
never publish to ForgeBox or GitHub.

To test the working copy as an installed module, run `box install <path to this checkout>`.
Then open a new shell. `box release help` should list the commands. The module uses its own
`box release publish` command to release itself.

Files in `commands/release/` contain the small command entry points. Files in `models/`
contain the release work. Rules that do not need CommandBox are kept in separate model
components so they are easier to test.

## More information

- [Detailed release guide](templates/RELEASE.md)
- [Optional GitHub Actions workflow](templates/github-release.yml)
- [Changelog](CHANGELOG.md)
- [MIT License](LICENSE)
