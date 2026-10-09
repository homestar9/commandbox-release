# commandbox-release

Releasing a CommandBox package: checking it, building it, and publishing a version to ForgeBox and a code host.

## Language

**Repository**:
The project's Git repository, as a release sees it: the project folder plus its release remote.
_Avoid_: repo, checkout (when you mean the whole repository)

**Release remote**:
The one Git remote that releases fetch from and push branches and tags to. It is `origin` unless release.json names another one.
_Avoid_: origin (when the name is configurable), upstream

**Host**:
The service that holds the release remote and shows releases, such as GitHub. Each host has its own provider.
_Avoid_: provider (for the service itself), platform, forge

**Production branch**:
The branch that holds published versions. Releases are built and tagged from it.
_Avoid_: master, main (when the name is configurable)

**Version tag**:
The Git tag that marks a published version: the tag prefix plus the version, such as `v1.2.0`.
_Avoid_: release tag

**Tag release mode**:
Whether a version tag can be released from the current commit: **new** (no tag exists yet), **existing** (the tag already points to this commit), or **conflict** (the tag points elsewhere, or the remote cannot be checked).
_Avoid_: tag status, tag mode

**Practice run**:
A run that checks and builds the package but publishes, tags, and pushes nothing.
_Avoid_: dry run (in user-facing text)
