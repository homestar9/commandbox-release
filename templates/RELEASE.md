# Release this project

Release settings are in `release.json` in the project root. The commands come from the
[commandbox-release](https://github.com/homestar9/commandbox-release) CommandBox module.
Files that must stay out of the package are listed under `ignore` in `box.json`.

## Set up your computer once

- Install CommandBox. Run `box version` to check it.
- Install commandbox-release with `box install commandbox-release`. Update it later with
  `box update commandbox-release --system`.
- Sign in to GitHub CLI with `gh auth login` when the project creates GitHub Releases.
- Sign in to ForgeBox with `box forgebox login` when the project publishes there.
- Make sure you can start the test server unless `runTests` is `false` in `release.json`.
- Check that `branch` in `release.json` names the production branch. This is usually `main`
  or `master`. For Gitflow projects, do not use `develop` or `release/*`.

Check the full setup with:

```
box release check
```

## Write release notes while you work

Add each change under `## [Unreleased]` in the changelog. Write for the people who use the
project. This text becomes the GitHub Release description. The `[Unreleased]` section must
contain at least one note before a release. Add a simple note such as `- Maintenance release`
when there are no user-facing changes.

## Release in one command

Run these from the production branch:

```
box release publish patch --dryRun   # practice: nothing is written, published, or pushed
box release publish patch            # bug fixes           1.0.0 -> 1.0.1
box release publish minor            # new features        1.0.0 -> 1.1.0
box release publish major            # breaking changes    1.0.0 -> 2.0.0
```

The command:

1. checks Git, the branch, the changelog, and the sign-ins;
2. updates the branch from origin;
3. changes the version in box.json and moves the `[Unreleased]` notes into a dated section;
4. commits `Release 1.0.1`;
5. runs the tests and builds a checked zip file;
6. publishes to ForgeBox when `publish.forgebox` is `true`; and
7. creates the tag and the GitHub Release when `publish.github` is `true`.

If a step fails after the commit, the message tells you what to do. The version is committed
on your computer, so after the fix you run `box release publish` without a level.

## Release in separate steps

Use this flow to review or commit the version change yourself:

```
box release bump patch               # box.json and changelog change; nothing is committed
git add box.json CHANGELOG.md
git commit -m "Release 1.0.1"
box release check                    # optional
box release publish --dryRun         # optional practice
box release publish
```

Replace `CHANGELOG.md` and `1.0.1` with your project's values. If you use GitKraken or another
Git app, stage only those two files, review them, and commit them as `Release 1.0.1`.

`release publish` without a level never changes the version. It publishes whatever version
box.json contains.

## Alpha, beta, and other prereleases

Version numbers follow SemVer. A prerelease such as `1.2.0-beta.3` comes before `1.2.0`.
Finishing that beta produces `1.2.0`, not `1.2.1`.

```
box release publish minor beta          # start:  1.1.0 -> 1.2.0-beta.1
box release publish prerelease          # update: 1.2.0-beta.1 -> 1.2.0-beta.2
box release publish minor               # finish: 1.2.0-beta.2 -> 1.2.0
```

The same levels work with `box release bump`. Use `prepatch` or `premajor` to start a
prerelease of the next patch or major version. Add a label such as `alpha` or `rc` after the
level to change the label.

The command will not start the next minor prerelease while another prerelease is active. This
rule prevents an accidental change from `1.2.0-beta.3` to `1.3.0-beta.1`. Use `prerelease` to
update the active prerelease, or `box release bump preminor --allowPrereleaseRetarget` when
you intend to change its target version.

GitHub marks a version as a prerelease when the version contains a hyphen.

| Level | What it does |
| --- | --- |
| `patch`, `minor`, `major` | Changes a normal version. For an active prerelease, it finishes the version that the prerelease targets. With a label after it, such as `minor beta`, it starts a prerelease of that level instead. |
| `prerelease` | Updates an active prerelease, such as `beta.3` to `beta.4`. |
| `prepatch`, `preminor`, `premajor` | Starts a prerelease. The default label is `beta`. |
| `none` | Keeps the version and dates the changelog. Use it for a first release when box.json already has the right version. |

## Gitflow guide

Gitflow uses branches for different stages of development:

- `develop` collects completed features.
- `release/<version>` prepares one release.
- The production branch contains published releases.

The `branch` setting always names the production branch. Gitflow creates the version tag
when the release is finished, so the tool never creates a second one. `release publish`
notices a tag that already points to the checked-out commit and uses it.

`box release publish <level>` refuses to run on a `release/*` or `hotfix/*` branch and prints
the steps below instead.

### Use GitKraken

GitKraken's **Finish release** action merges the release into production and `develop`, and
creates the tag. Set the version tag prefix under **Preferences > Gitflow** so it matches
`tagPrefix` in release.json. The usual prefix is `v`. See the
[GitKraken Gitflow documentation](https://help.gitkraken.com/gitkraken-desktop/git-flow/).

1. Start a release in GitKraken. It creates `release/1.2.0` from `develop`.
2. On `release/1.2.0`, run `box release bump minor`. Review and commit box.json and the
   changelog as `Release 1.2.0`.
3. Optional: run `box release test` and `box release publish --dryRun` on the release branch.
   The practice run warns that the real release must run from the production branch.
4. Select **Finish release**. GitKraken merges both branches and creates `v1.2.0`.
5. Push production and `develop`. Check out the updated production branch.
6. Run `box release publish`. It finds `v1.2.0` at the current commit, pushes the tag when
   origin does not have it, runs the tests, builds, publishes, and creates the GitHub Release.

Choose one publishing method. If a GitHub Actions job publishes when a tag is pushed, push the
tag and let the job run instead of step 6.

A hotfix works the same way on a `hotfix/<version>` branch. It usually changes the patch
version.

### Use the `git-flow` extension

Set the extension's version tag prefix to match `tagPrefix`:

```
git config gitflow.prefix.versiontag v
```

Then:

```
git flow release start 1.2.0
box release bump minor
git add box.json CHANGELOG.md
git commit -m "Release 1.2.0"
git flow release finish 1.2.0        # merges both branches and creates v1.2.0
git push origin main develop
git switch main
box release publish                  # uses v1.2.0 and pushes it
```

`git flow release finish -n` finishes without a tag. In that case `box release publish`
creates the tag itself.

### Use plain Git or pull requests

1. Create `release/1.2.0` from an updated `develop`.
2. On the release branch, run `box release bump minor`, then commit and push the branch.
3. Merge the release branch into production and `develop`, with pull requests when needed.
4. Check out the updated production branch and run `box release publish`. The command creates
   and pushes the tag.

### Handle a tag that exists before Finish

First check whether the tag exists only on your computer or was pushed to origin:

```
git fetch --tags origin
git show --no-patch --decorate v1.2.0
git ls-remote --tags origin refs/tags/v1.2.0
```

- If both merges are complete and `v1.2.0` points to production `HEAD`, do not run Finish
  again. Push any branches that still need to be pushed, and then run `box release publish`.
- If a merge is missing, merge the release into production and `develop` by hand or with pull
  requests. The tag must point to the final production `HEAD` before `box release publish` can
  use it.
- If the tag was created by mistake and exists only on your computer, delete it before using
  GitKraken Finish. In GitKraken, right-click the tag and select **Delete locally**. On the
  command line, run `git tag -d v1.2.0`.
- If the tag is on origin, was already published, or points to another commit, do not delete
  or move it without checking. The version may already be in use. Review the release history.
  Use a new version or plan a specific repair with your team.

## Test on more than one engine

```
box release test
```

With `engines` listed in release.json, the command runs the full test suite on each engine,
one at a time. A failed engine does not stop the other engines. Without engines, it runs the
tests once against the test server.

## Skip tests that already ran

```
box release publish --skipTests
```

This skips the test suite and prints a clear warning.

## Finish a release after a failure

All checks that can stop a release run before publishing. A later step can still fail after a
package was published. Do not run the full release again in that case. The version is already
published, so the checks will stop. Run:

```
box release resume
```

It creates the tag when it is missing, pushes it when origin does not have it, and creates the
GitHub Release from the zip under `.artifacts`. Run `box release notes 1.0.1` to see the notes
for one version.

## Common problems

| Message | How to fix it |
| --- | --- |
| `Command "release" cannot be resolved` | Install the module with `box install commandbox-release`. |
| `This project requires commandbox-release X or newer` | Run `box update commandbox-release --system`. |
| `You have uncommitted changes` | Commit or stash the changes first. The release will not replace uncommitted work. |
| `You are on a Gitflow release branch` | Run `box release bump`, commit, finish the release, and publish from the production branch. |
| `The test server ... did not answer` | Start the server, or set `runTests` to `false` in release.json. |
| `Could not find the GitHub CLI` | Install it and open a new terminal. A terminal uses the PATH value from when it started. |
| `Permission denied (publickey)` | Git cannot sign in to the remote. Add your SSH key to GitHub, or use an HTTPS remote. |
| `does not have a "## [1.0.1]" section` | Run `box release bump` to move the notes into a dated section, or use `box release publish patch`. |
| `The "## [Unreleased]" section is empty` | Write at least one release note. No files were changed. |
| `is not a prerelease` | Use `publish minor beta` or `bump preminor beta` to start a prerelease. |
| `The package is missing box.json` or `ModuleConfig.cfc` | A pattern in the box.json `ignore` list matches a required file. Fix the list. |
| `Tag v1.0.1 already exists on origin` | That version was already released. Use a new version. |
| `Tag v1.0.1 points to a different commit on origin` | The local and remote tags point to different commits. Do not move the published tag. Check the release history or use a new version. |
| `tag v1.0.1 is local only` | No action is needed. `box release publish` pushes the tag before creating the GitHub Release. |
| `Version X is committed locally and nothing was published` | Fix the reported problem, and then run `box release publish` without a level. |
