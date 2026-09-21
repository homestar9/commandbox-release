# Changelog

This file lists the important changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The module is now `commandbox-release`. Install it with `box install commandbox-release`
  and update it with `box update commandbox-release --system`. The `release` command
  namespace stays the same.
- Project settings moved from `build.json` to `release.json`. `minimumKitVersion` is now
  `requires`.
- `box release publish` replaces `release run`. Without a level it publishes the version in
  box.json. With a level, such as `box release publish patch`, it changes the version, moves
  the [Unreleased] notes, commits `Release x.y.z`, and then publishes.
- `box release publish` notices a tag that already points to the current commit, such as a
  tag created by Gitflow or GitKraken, and uses it. The `--existingTag` flag is gone.
- `box release publish <level>` refuses to run on a Gitflow `release/*` or `hotfix/*` branch
  and prints the steps for those branches instead.
- `box release init` asks whether the project is a module (ForgeBox + GitHub) or a web app
  (GitHub only), and whether to run the tests. `--yes` accepts the defaults. It offers to
  create box.json when the folder has none.
- The package now contains every file except the ones matched by the box.json `ignore` list,
  the same list ForgeBox applies. `box release init` adds the recommended patterns to it. The
  zip attached to the GitHub Release and the ForgeBox package now contain the same files.
- The build stops when the ignore list removes box.json or a module's ModuleConfig.cfc.
- `box release test` replaces `release engines`. Without engines it runs the tests once.
- `box release resume` replaces `release github`.
- `box release bump` prints the granular next steps and ends with `box release publish`.

### Removed

- `release migrate` and every compatibility path for 1.x and 2.x projects. See the README
  section "Upgrading from 1.x or 2.x".
- The regex `excludes` and `excludesAdd` settings. Release commands stop with a message when
  release.json still contains them.
- The `version=` argument on the publish command. box.json is the only source of the version.

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
