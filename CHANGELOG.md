# Changelog

This file lists the important changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.7.0] - 2026-10-29

### Added

- `testRunner` in `release.json` can be a path on the project's CommandBox server, such as
  `"/tests/runner.cfm"`. The release finds the server's address when it runs the tests, so
  `release.json` does not repeat the port. A full URL still works.
- A path in `testbox.runner` in `box.json` works too. Before, it stopped every release command
  with "testRunner must be a full URL".
- With a runner path, each engine in `engines` can use its own port. `box release test` reads
  each engine's address after it starts the engine.

### Changed

- When neither `release.json` nor `box.json` sets a test runner, the release uses
  `/tests/runner.cfm` on the project's server. It used `http://127.0.0.1:60299/tests/runner.cfm`.
  `box release init` writes the path into new `release.json` files. `box testbox run` uses the
  same default.

## [3.6.0] - 2026-10-26

### Added

- A new `testCommand` setting in `release.json` runs the tests with a CommandBox command,
  such as `"testCommand": "run-script test"`. Use it for a project whose tests run inside
  CommandBox without a web server, such as a CommandBox module. `box release test`,
  `box release publish`, and `box release gitflow` run it in a new `box` process from the
  project root. If the command fails, the release stops the same way it stops for failing
  tests. `--skipTests` skips it.
- With `testCommand`, the release does not check `testRunner` or need a test server. The
  setting cannot be used with `engines`. `release.json` with both stops with an error.
- `box release check` shows the test command and checks that it can find `box`.
- `box release init` suggests `run-script test` for a CommandBox module that has a `test`
  script and no TestBox runner URL.
- A new `hooks.beforePublish` setting in `release.json` runs a CommandBox command after the
  tests and the build pass and before anything is published or pushed. For example,
  `"hooks": { "beforePublish": "deploybot env push --yes" }` sends a web app's settings to the
  server before the push starts a deploy. `box release publish` and `box release gitflow` run
  it. If the command fails, the release stops and nothing is published. A practice run shows
  the command without running it.
- `box release publish` and `box release gitflow` have a new `--skipHooks` flag. It skips the
  `beforePublish` command.
- `box release check` shows the `beforePublish` command and checks that it can find `box`.
- `box release publish` and `box release gitflow` can fix a Gitflow finish that tagged a
  version before `box.json` changed. This happens when you finish a release or hotfix in
  GitKraken or `git flow` before you change the version. The commands show the steps and ask
  whether to do them. If you answer `y`, box release creates `hotfix/1.0.1` (or
  `release/1.1.0` for a minor or major version) from production and deletes the local tag.
  Then it changes the version, merges into both branches, publishes, and pushes. A new
  `--fixTag` flag does this without asking, such as in CI. The commands never ask in a practice
  run or when nobody can answer. See "Mistakes box release can fix" in the README.
- A new `prereleaseBranches` setting in `release.json` lists branches that may publish
  prerelease versions, such as `"prereleaseBranches": ["develop"]`. On a listed branch,
  `box release publish preminor alpha`, `box release publish prerelease`, and
  `box release publish` commit, tag, and push the prerelease on that branch and mark the GitHub
  Release as a prerelease. Stable versions still publish from the production branch. A stable
  level on a listed branch stops and points to `box release gitflow`. The list is empty by
  default, so existing projects behave as before. See "Publish prereleases from develop" in the
  README.
- `box release check` shows the prerelease branches and accepts a listed branch when `box.json`
  holds a prerelease.

### Changed

- `box release package` on a prerelease branch no longer adds `-snapshot` to a prerelease
  version. The package gets the build ID, as it does on the production branch.
- `box release gitflow` without a level on `develop` stops when `develop` is a prerelease
  branch and `box.json` holds a prerelease that is newer than production. Before, it created a
  release branch for the prerelease and published it from production.
- When a Gitflow merge into a prerelease branch conflicts on `box.json`, the manual steps say
  which version to keep. This happens when a hotfix meets a prerelease on `develop`.
- When a prerelease line ends with a stable version and `[Unreleased]` is empty, the error says
  that the prerelease notes stay in their own sections and asks for notes for the stable version.

- The build stops when the package contains a `.env` file, such as `.env.production`. These
  files can hold passwords and keys. Example files such as `.env.example` are still allowed.
  Add `"**/.env*"` to the `box.json` ignore list to leave them out.
- The GitHub Actions workflow template passes `skipHooks=true`. Copy the change into an
  existing `.github/workflows/release.yml` if you set `hooks.beforePublish`.
- `box release gitflow` merges the changelog into `develop` when `develop` added notes while a
  release or hotfix branch was open. It keeps the new notes under `[Unreleased]` and removes
  the notes that the release published. Before, it stopped with the message "The [Unreleased]
  notes in CHANGELOG.md changed on both branches" and asked you to merge by hand.

### Fixed

- `box release publish <level>` checks the new version's tag before it changes any files. Before,
  it made the "Release x.y.z" commit and then stopped because the tag already existed.
- A Gitflow finish in GitKraken or `git flow` can tag a version, such as `v1.0.1`, before
  `box.json` changes. `box release publish` and `box release gitflow` now explain how to fix
  this. When the tag is only on your computer, delete it, create `hotfix/1.0.1`, and run
  `box release gitflow patch`. Before, the message suggested `box release bump patch`, which
  stopped on the same tag.
- When a prerelease version was already released, `box release publish` and `box release check`
  now suggest `box release bump prerelease`. Before, they suggested `box release bump patch`,
  which would have finished the prerelease.

## [3.5.3] - 2026-10-22

### Fixed

- `box release gitflow` no longer warns that the build skipped the tests after they passed
  on the release or hotfix branch. The build now says which branch passed the tests.

## [3.5.2] - 2026-10-18

### Changed

- `box release gitflow` on a hotfix branch without a level now updates a prerelease. For
  example, `1.0.0-beta.2` becomes `1.0.0-beta.3`. Before, it published `1.0.0`. Use
  `box release gitflow patch` to finish the prerelease. With `preid` and no level, the hotfix
  changes the label, such as `1.0.0-beta.2` to `1.0.0-rc.1`.

## [3.5.1] - 2026-10-12

### Added

- Added default `box.json` ignore patterns for common files that should not be in a package. 

## [3.5.0] - 2026-10-12

### Changed

- `box release gitflow` now combines the changelog when it is the only file with a merge
  conflict. It keeps the `[Unreleased]` notes on `develop` and adds the new version section.
  A part of the changelog that changed on both branches still stops the command with the
  manual merge steps, and so does a conflict in any other file.

## [3.4.0] - 2026-10-12

### Added

- `box release check` and `box release publish` list recommended `box.json` ignore patterns
  that are missing from the project's ignore list. These patterns keep files out of the
  package. Run `box release init --yes` to add them. Missing patterns do not stop a release.
- The build shows the zip size. It warns when the package contains `node_modules` or is
  larger than 50 MB.
- The README explains how to add new recommended ignore patterns to an existing project.

### Changed

- Without `--force`, `box release init` skips the setup questions when `release.json` exists.
  Setup keeps existing settings and changelog files and adds missing ignore patterns.
  Use `--force` to replace those files. Without `--yes`, setup asks the questions again.

## [3.3.0] - 2026-10-09

### Changed

- `box release publish` with an existing tag now pushes the production branch when `origin`
  does not have the tagged commit. The checks report this before anything is published.
  They stop if `origin` has commits on that branch that your checkout does not have.

## [3.2.0] - 2026-10-09

### Added

- `box release gitflow` merges a release or hotfix branch and publishes the package.
  On `develop`, it creates a release branch first. It changes the version when needed and
  runs the tests. It merges into `develop` and the production branch before publishing.
  Then it pushes both branches and deletes the release or hotfix branch by default.
- The `remote` setting in `release.json` names the Git remote for releases. The default is
  `origin`.

### Changed

- `box release publish <level>` on a Gitflow release or hotfix branch now suggests
  `box release gitflow`.
- Clearer Gitflow comments and command messages. The README now explains each step for a
  first release and no longer includes instructions for versions before 3.0.0.
- Release commands now stop with a clear message when the release remote does not exist.
  `box release check` reports it too.

### Fixed

- The GitHub Release is now created in the repository of the release remote. Before, GitHub
  CLI could choose another repository when the checkout had more than one remote.
- `box release check` now uses the same tag rule as `box release publish`. A version tag at the
  current commit that is already on the remote is reported as ready. A remote that cannot be
  checked is reported as a problem.
- `box release publish` and `box release resume` now accept an annotated tag that is already
  on the remote. GitKraken and git flow create annotated tags. Before, the command reported
  that the tag pointed to a different commit.
- The package build now reads the branch and commit from Git. This works in linked worktrees
  and when the project is a folder inside a larger repository.
- `box release gitflow` now shows SSH key help when `git fetch` is refused.

## [3.1.1] - 2026-10-08

### Fixed

- NPM dependencies are now shared ignored files between modules and web apps.

## [3.1.0] - 2026-10-08

### Changed

- The module is named `commandbox-release`. Install it with `box install commandbox-release`
  and update it with `box update commandbox-release --system`. Commands still start with
  `release`.
- Project settings are now in `release.json` instead of `build.json`. The
  `minimumKitVersion` setting is now called `requires`.
- `box release publish` replaces `release run`. With no level, it publishes the version in
  `box.json`. With a level, such as `patch`, it changes the version, dates the release notes,
  commits the changes, and publishes.
- `box release publish` uses an existing version tag if it points to the current commit. You
  no longer need `--existingTag` for tags made by Gitflow or GitKraken.
- `box release publish <level>` stops on Gitflow `release/*` and `hotfix/*` branches. It shows
  the steps to finish the release from those branches.
- `box release init` asks where to publish the project and whether to run tests. ForgeBox
  publishing is on by default when `box.json` or `ModuleConfig.cfc` shows that the project
  is a module. Use `--yes` to accept the default answers. If `box.json` is missing, setup
  offers to create it.
- Packages now use the `box.json` `ignore` list to leave files out. ForgeBox uses the same
  list, so its package and the GitHub zip contain the same files. `box release init` adds
  common ignore patterns.
- The build stops if an ignore pattern leaves out `box.json`, or `ModuleConfig.cfc` when
  the project has one.
- `box release test` replaces `release engines`. It runs tests once if no engines are listed.
- Test runs list each failed test by bundle, suite, and spec. With engines, the final results
  list them under each engine.
- When the TestBox runner errors or times out instead of returning results, the test run
  shows the runner's error. It no longer reports this as failing tests.
- Test runs ask the runner to stop after the first spec file with a failure (TestBox
  `eagerFailure`). The standard TestBox runner ignores this option. The README shows the
  two-line runner change that turns it on.
- `box release resume` replaces `release github`.
- `box release bump` now shows the steps to commit the change and run `box release publish`.
- `box release publish` stops when `git pull` brings in new commits. Run it again to check the
  updated project.
- `stagingDir` and `artifactsDir` must be folders inside the project. The build deletes these
  folders before each run.
- When `[Unreleased]` looks empty because a group heading such as `## Added` follows it,
  `box release bump` and `box release publish <level>` name that heading. They say to use
  `### Added`, because `##` starts a new version section.

### Fixed

- The GitHub Actions template now signs in to ForgeBox with `box config set
  endpoints.forgebox.APIToken`.

### Removed

- `release migrate` and support for 1.x and 2.x project settings. See "Upgrading from 1.x or
  2.x" in the README.
- The `excludes` and `excludesAdd` settings. Release commands explain the problem if these
  settings remain in `release.json`.
- The `version=` argument for publishing. The publish command reads the version from
  `box.json`.

## [2.0.1] - 2026-09-13

- Cleaned up README and code documentation.

## [2.0.0] - 2026-09-13

### Changed

- `build-template` is now a CommandBox module. Install it once on each computer with
  `box install build-template`. You no longer need to copy a `build` folder into each project.
- Build tasks are now commands in the `release` namespace. The commands are `box release run`,
  `release check`, `release bump <level>`, `release package`, `release engines`, `release init`,
  `release notes`, `release github`, and `release migrate`. Run `box release help` to list them.
- Project settings now use `build.json` in the project root. The kit can still read the old
  1.x file at `build/build.json`. It prints a notice until `release migrate` moves the file.
- A project can set `minimumKitVersion` in `build.json`. Release commands stop and print the
  update command when the installed kit is too old.
- Release commands now find the project from any folder inside it.
- Use `box update build-template --system` to update the kit.

### Removed

- Projects no longer need the copied `build` folder, `Update.cfc`, `build-kit.json`,
  `templateVersion`, or scripts added to box.json by the installer.
- `release init` no longer adds scripts to box.json. `release migrate` updates old 1.x scripts
  to use the new commands. Existing `box run-script release` calls continue to work.

### Migration from 1.x

1. Run `box install build-template`.
2. Run `box release migrate --dryRun` in each project. Then run `box release migrate`, review
   the changes, and commit them.
3. Install the module before the release step in CI. See `templates/github-release.yml`.

## [1.5.0] - 2026-09-13

### Added

- `build-kit:update` (`build/Update.cfc`) updates the kit files copied into a project. It can
  download the latest build-template release or use `:source=<folder or zip>`. It replaces kit
  files under `build/` but keeps `build/build.json`. It adds new box.json scripts, records the
  kit version, and prints changelog entries added since the previous version. Use `:version=`
  to choose a release. Use `:dryRun=true` to list changes without applying them.
- `build/build-kit.json` records the kit version and repository. The installer now writes the
  real kit version to `templateVersion` instead of always writing `1.0.0`.
- `release:check` now reports whether the release tag exists on origin.

### Changed

- `release:existing-tag` now checks origin before publishing. It pushes a local-only tag right
  before creating the GitHub Release. It stops when origin has the same tag at another commit.
  Before this change, an unpushed Gitflow tag caused the last release step to fail after the
  package was already published to ForgeBox.
- The box.json script list moved to `build/lib/PackageScriptService.cfc`. The install and
  update tasks now use the same list.

## [1.4.2] - 2028-08-10

### Changed

- `bump:beta`, `bump:alpha`, and direct `preminor` calls now stop before changing an active
  prerelease to a new target. Use `:allowPrereleaseRetarget=true` to allow that change.

## [1.4.1] - 2028-08-07

- Updated the logo.

## [1.4.0] - 2028-08-07

### Added

- Added TestBox tests for version rules, changelog parsing, project settings, public task APIs,
  multiple-engine workflows, installation, package builds, and safe release practice runs.

### Changed

- Build task components now use direct names and smaller workflow functions.
- Developer documentation now uses plain language for people who are new to the project.
- Version, changelog, and project detection rules now use small internal services under
  `build/lib/`.
- The multiple-engine guide now explains that all configured engines run before the command
  reports any failures.

## [1.3.0] - 2028-08-03

### Added

- Added `release:existing-tag`. This task publishes a release tag created while finishing a
  Gitflow release in a tool such as GitKraken.

### Changed

- The Gitflow guide now gives the branch steps in order. Create the release branch first.
  Change the version and commit on that branch. Then finish the release into production and
  `develop`.
- Git instructions now include the matching review, stage, commit, and push steps for people
  who use GitKraken or another Git app.
- The guide now has separate GitKraken instructions for valid, old, and already published tags.

## [1.2.0] - 2026-07-31

### Added

- Added a Gitflow release guide for plain Git, pull requests, `git-flow`, and hotfixes.
- Added a mode that publishes tags created by Gitflow or tag-based CI jobs.
- Added `release:skip-tests` as a clear name for the existing option that skips release tests.

### Changed

- A release practice run can run from a non-production branch and prints a warning. A real
  release must still run from the configured production branch.
- Release updates now allow fast-forward changes only. Normal releases now reject tags that
  already exist locally or on the remote.
- Setup now uses Gitflow's production branch when it is configured. Git instructions now list
  separate review, stage, and commit steps for developers who are new to Git.
- The optional GitHub Actions workflow can publish an existing tag. It requests only the
  repository content permission needed to create the release.

## [1.1.0] - 2026-07-30

### Added

- New projects now get a complete exclusion list in `build/build.json`. Module packages
  exclude common ColdBox development files. Applications keep possible deployment files such
  as `modules`, `.htaccess`, and `.well-known`.
- Setup now finds `server.json` and root-level `server-*.json` files in filename order. It
  names each engine from `app.cfengine`, the server name, or the filename.

### Changed

- The included `build.json` is now marked as a starter file that setup can replace. Setup does
  not replace an existing unmarked or invalid file unless you use `:force=true`.

## [1.0.0] - 2026-07-29

### Added

- Added the first build kit tasks: `Build`, `Release`, `Bump`, `TestEngines`, `Install`, and
  `Doctor`. They share one settings file at `build/build.json`.
- `box run-script release` checks the project, updates it from the remote, runs tests, builds
  the package, publishes to ForgeBox, creates a Git tag, and creates a GitHub Release. It uses
  the changelog notes and attaches the zip file.
- `release:check` reports whether a project is ready to release. It prints a fix for each
  problem.
- `release:dryrun` runs a release practice run without publishing.
- `release:hotfix` and `:skipTests=true` skip the tests and print a warning.
- `test:engines` runs the tests on each engine in order. It stops at the first failure and
  lists the engines that passed before the failure.
- `bump:major`, `bump:minor`, and `bump:patch` change the version and move `[Unreleased]` notes
  into a dated section. Prereleases follow SemVer. For example, `bump:patch` changes
  `1.2.0-beta.3` to `1.2.0`, not `1.2.1`.
- `bump:beta`, `bump:alpha`, and `bump:prerelease` start or update prereleases. Use `:preid`
  for another prerelease label.
- `Install.cfc` sets up a project in one command. It reads the test runner from `box.json` and
  creates the engine list from root-level `server-*.json` files.
- The build checks packages before publishing. It compares the number of staged files with the
  number of files in the zip and stops when the numbers differ.
- Packages include the short Git commit hash for the source used to build them.
- `excludesAdd` adds entries to the default exclusion list. Excluding one more file requires
  one new setting.
- Added an optional GitHub Actions workflow under `build/templates/`.
