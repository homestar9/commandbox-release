# commandbox-release

CommandBox module (CFML) that adds `box release *` commands. User docs: README.md.

## Test

- `box install` once to get TestBox (into `testbox/`, git-ignored).
- `box run-script test` runs every spec in `tests/specs/` and loads this working copy as the module.
- One spec: `box task run taskFile=tests/Run.cfc :bundles=tests.specs.VersionServiceSpec`
- Integration specs build temp projects in `.test-work/` with a local Git remote. They never publish.

## Layout and rules

- `commands/release/*.cfc` handle only arguments. The release logic is in `models/`.
- Models never call `error()`. They `throw( type = "Release.*" )`, and the command turns that
  into a command error. This keeps models testable without running a command.
- Add each user-visible change under `## [Unreleased]` in `CHANGELOG.md` (Keep a Changelog sections).
- User-facing text (messages, README, CHANGELOG, doc comments) uses short, plain sentences.
  Match the existing style.
- `testbox/` is a vendored dependency. Don't edit or search it.
