# commandbox-release

![commandbox-release logo](https://raw.githubusercontent.com/homestar9/commandbox-release/refs/heads/master/commandbox-release-logo.avif)

`commandbox-release` adds namespaced release commands to
[CommandBox](https://www.ortussolutions.com/products/commandbox), which enable you to easily:

- Update/bump project version
- Automatically populate a changelog with release date and version number
- Run TestBox tests
- Build and check a release zip file and
- Publish a package to Github and/or Forgebox.

It supports both modules and web apps. Forgebox storage is optional. Each project stores its release settings in a `release.json`, in your project root.

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

A project can set `requires` in `release.json` to choose the oldest module version it supports.
If your installed version is too old, release commands stop and show how to update it.

## Set up a project

Go to the project's root folder and run:

```bash
box release init
```

The command asks where to publish the project and whether to run tests before each release.
Then it:

- creates `release.json` from your answers and the settings it finds in the project;
- creates `CHANGELOG.md` when the project does not already have one;
- adds patterns to the `ignore` list in `box.json`. These patterns keep test, server, and editor
  files out of the package; and
- adds its `.tmp/` and `.artifacts/` folders to `.gitignore`.

ForgeBox publishing is on by default when the project is a module. That means the `box.json`
`type` is a module type, such as `modules` or `commandbox-modules`, or the project root has
`ModuleConfig.cfc`. Other projects, such as web apps, publish only to GitHub by default. You
can change `publish.forgebox` in `release.json` at any time.

Use `--yes` to accept the default answers. Use `--docs` to copy `RELEASE.md` into your
project. Use `--ci` to copy a GitHub Actions workflow to `.github/workflows/release.yml`. You
can run setup again. It keeps existing files unless you use `--force`.

If the folder has no `box.json` yet, the command offers to create one.

## Release and Publish a Module or Web App

```bash
box release init                       # answer the setup questions
# Add notes under [Unreleased] in CHANGELOG.md.
box release publish patch --dryRun     # build the zip without changing the version
box release publish patch              # change the version and publish the release
```

## Ways to release

### Change the version and publish in one command

```bash
box release publish patch              # 1.0.0 -> 1.0.1 for a bug fix
box release publish minor              # 1.0.0 -> 1.1.0 for a new feature
box release publish major              # 1.0.0 -> 2.0.0 for a breaking change
box release publish minor beta         # 1.0.0 -> 1.1.0-beta.1 to start a prerelease
```

Run these commands on your production branch, such as `main`. The command first checks Git,
the changelog, and your service sign-ins. Then it updates the branch from `origin`, changes the
version, and moves the `[Unreleased]` notes into a dated section. It commits the changes as
`Release 1.0.1`, runs the tests, and builds and checks the zip. It publishes only after those
steps pass. Finally, it creates and pushes the tag and creates the GitHub Release.

If a step fails after the commit, fix the reported problem. The version change is already
committed on your computer. Run `box release publish` without a level to continue.

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

### Gitflow in one command

Gitflow is a way to manage release branches and tags. `box release gitflow` does the Gitflow
release steps and publishes the result:

```bash
box release gitflow minor              # on develop: create release/1.1.0 and finish it
box release gitflow                    # on a release branch: finish it
box release gitflow                    # on a hotfix branch: finish it as a patch
box release gitflow minor --dryRun     # show the steps and build the zip
```

To finish a branch, the command:

1. gets new commits from `origin` for develop, the production branch, and the release branch;
2. changes the version and dates the `[Unreleased]` notes, unless the branch already has the
   new version, and commits the change as `Release 1.1.0`;
3. runs the tests on the release branch;
4. merges the branch into `develop` and the production branch;
5. publishes from the production branch, like `box release publish`; and
6. pushes both branches, deletes the release branch, and switches to `develop`.

The merges happen on your computer. Nothing is pushed until the build passes. If a step fails
before publishing, fix the problem on the release branch and run `box release gitflow` again.
Merges that are already done are skipped.

A hotfix branch must already have the fix, so the command only finishes it. Create the hotfix
branch from the production branch and commit the fix first. If a release branch is open, the
command warns you to merge the hotfix into it yourself.

Branch names come from your Gitflow settings in Git config. GitKraken and `git flow` store
them there. The defaults are `develop`, `release/`, and `hotfix/`. Use `--keepBranch` to keep
the release branch.

### Gitflow and GitKraken

You can also finish the release in GitKraken. GitKraken can finish a Gitflow release and
create its version tag. Change the version on the release branch, then publish it from the
production branch:

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
`release/*` and `hotfix/*` branches and shows these steps. The
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
| `box release gitflow minor` | Creates a Gitflow release branch on develop, merges it, and publishes. On a release or hotfix branch, it finishes that branch. |
| `box release bump patch` | Changes the version and dates the release notes. It does not commit. |
| `box release check` | Finds problems that would stop a release. |
| `box release test` | Runs the tests once, or on each engine listed in `release.json`. |
| `box release package` | Builds and checks the zip file without publishing. |
| `box release notes` | Shows the release notes for the current version. |
| `box release resume` | Finishes a release that stopped after publishing. |

Run `box help release publish` to see all help for one command.

## Settings

The setup command creates `release.json` in the project root. Edit that file to change how
release commands work.

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

If `release.json` does not set `publish.forgebox`, a module publishes to ForgeBox and any
other project does not. Set the value yourself to override that default.

### Do not run tests during the build

Use this setting when another system, such as CI, runs the tests:

```json
{
    "runTests": false
}
```

### Keep files out of the package

The package includes project files unless a pattern in the `box.json` `ignore` list leaves
them out. A pattern is a rule that matches file paths. ForgeBox uses the same list. This keeps
the GitHub zip and the ForgeBox package in sync. Setup adds common patterns, and you can edit
the list at any time.

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
- `!/.htaccess` keeps a file that an earlier pattern removed. Web apps use this to ship
  `.htaccess` and `.well-known/` while `**/.*` removes the other hidden files.

The package also leaves out `.git`, `.gitignore`, `release.json`, `.tmp`, and `.artifacts`.
The build does not use `.gitignore` to choose package files. For example, `.gitignore` may
exclude a `modules/` folder that the running project needs. The build stops if the `box.json`
ignore list excludes `box.json`, or `ModuleConfig.cfc` when the project has one.

### Test more than one CFML engine

During setup, the command finds `server.json` and `server-*.json` files in the project root.
It adds each one to `engines` in filename order. Remove servers you do not want to test.

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

When tests fail, the command lists each failed test as `bundle > suite > spec -- message`
after the run. With engines, the final results list the failed tests under each engine.

### Stop the tests at the first failure

The release commands ask the test runner to stop after the first spec file (bundle) that has
a failed test, which is the TestBox `eagerFailure` option. The rest of that file still runs, and
later files are skipped.

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
| `requires` | the version that created the file | The oldest commandbox-release version this project can use. |
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
| `This project has build.json from build-template 1.x or 2.x` | See [Upgrading from 1.x or 2.x](#upgrading-from-1x-or-2x). |
| `You have uncommitted changes` | Commit or stash the changes, and then run the command again. |
| `You are on a Gitflow release branch` | Run `box release gitflow` on that branch. Or run `box release bump patch`, commit the changes, finish the release, then publish from `master`. |
| `... could not be merged into develop` | Merge the branch by hand and fix the conflicts. Then switch to the release branch and run `box release gitflow` again. |
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

## Upgrading from 1.x or 2.x

Version 3.0 renamed `build-template` to `commandbox-release`. It reads `release.json` instead
of `build.json`. The old settings are not converted for you. Update each project as follows:

1. Replace the module:

   ```bash
   box uninstall build-template --system
   box install commandbox-release
   ```

2. Delete the copied `build/` folder if the project still has one from version 1.x.
3. Delete `build.json` or `build/build.json`. Run `box release init`. Copy custom values such
   as `branch`, `engines`, and `tagPrefix` into the new `release.json`. Rename
   `minimumKitVersion` to `requires`.
4. Move custom `excludes` and `excludesAdd` rules to the `ignore` list in `box.json`. Write
   them as file patterns. A leading `/` matches only the project root. Without it, the
   pattern matches at any folder depth. Setup already adds common patterns.
5. Update scripts and CI steps: `release run` is now `release publish`,
   `release run --existingTag` is now just `release publish`, `release engines` is now
   `release test`, and `release github` is now `release resume`. `release migrate` is gone.

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
