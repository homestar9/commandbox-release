# Changelog

This file lists the important changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
