/**
 * Merges a Gitflow release or hotfix branch and publishes it for `box release gitflow`.
 *
 * On develop, it first creates a release branch, such as release/1.2.0. On a release or hotfix
 * branch, it uses the current branch. It changes the version when needed and runs enabled tests.
 * Then it merges into develop and the production branch, which holds published versions.
 * ReleaseService builds and publishes from production. This component then pushes both
 * branches and deletes the release or hotfix branch unless keepBranch is true.
 *
 * The merges happen on this computer. Nothing is pushed until the build passes. If a step
 * fails before publishing, fix the problem and run the command again on the release or hotfix
 * branch without a level. Git does not repeat merges that are already complete.
 *
 * Branch names come from the Gitflow settings in Git config. GitKraken and git flow both store
 * them there. The production branch comes from release.json.
 *
 * With fixTag on production, it first fixes a Gitflow finish that tagged a version without
 * changing box.json. See fixTaggedFinish().
 */
component extends="commandbox-release.models.BaseService" {

	property name="versionService"   inject="VersionService@commandbox-release";
	property name="changelogService" inject="ChangelogService@commandbox-release";

	/**
	 * Creates a release branch when needed, merges it, and publishes the package.
	 *
	 * @level      The version change, such as patch or minor. Without a level, use box.json's
	 *             version if it is newer than production. Otherwise, a hotfix uses prerelease
	 *             when box.json has a prerelease and patch for other versions. Other branches
	 *             require a level. The none level keeps the version and dates the release notes.
	 * @preid      A prerelease label. For example, minor with beta starts 1.1.0-beta.1.
	 * @dryRun     Shows the steps and builds from the current branch. Writes build files but
	 *             leaves branches, box.json, and the changelog unchanged. Does not publish or push.
	 * @skipTests  Skips the tests.
	 * @keepBranch Keeps the release or hotfix branch after the release.
	 * @skipHooks  Skips the beforePublish command in release.json.
	 * @fixTag     On production, fixes a Gitflow finish that tagged a version without changing
	 *             box.json. It creates a hotfix or release branch for the tagged version, deletes
	 *             the local tag, and then publishes from that branch. See fixTaggedFinish().
	 */
	function run(
		string level       = "",
		string preid       = "",
		boolean dryRun     = false,
		boolean skipTests  = false,
		boolean keepBranch = false,
		boolean skipHooks  = false,
		boolean fixTag     = false
	){
		if ( arguments.fixTag && repository().currentBranch() == variables.settings.branch ) {
			var finished = service( "ReleaseService" ).finishedWithoutVersion( arguments.level, arguments.preid );
			if ( finished.canFix ?: false ) {
				return fixTaggedFinish( finished, arguments );
			}
		}

		var flow = resolveBranches( arguments.level, arguments.preid );
		var plan = planVersion( flow, arguments.level, arguments.preid );
		if ( flow.kind == "start" ) {
			flow.branch = flow.releasePrefix & plan.version;
		}

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "PRACTICE RUN: Build files will be written. Branches, box.json, and the changelog will stay unchanged. Nothing will be published or pushed." )
				.line()
				.toConsole();
		}

		// 1. Check Git, service sign-ins, release notes, and branches before making changes.
		print.boldBlueLine( "=== Checking before the Gitflow release ===" ).toConsole();
		var release = service( "ReleaseService" );
		release.checkGitflowRelease(
			version      = plan.version,
			dryRun       = arguments.dryRun,
			requireNotes = plan.bump
		);
		checkBranches( flow );
		if ( len( plan.note ) ) {
			print.yellowLine( "  note  #plan.note#" ).toConsole();
		}

		if ( arguments.dryRun ) {
			return practice( flow, plan, release, arguments.preid, arguments.skipTests, arguments.keepBranch, arguments.skipHooks );
		}

		// 2. Get commits from the project's Git remote. If the current branch changes,
		//    stop so the next run can check the updated files.
		if ( variables.settings.gitSync ) {
			syncBranches( flow );
		}

		// 3. Create the release branch from develop.
		if ( flow.kind == "start" ) {
			try {
				repository().createBranch( flow.branch, flow.develop );
			} catch ( "Release.Git" exception ) {
				return stop( exception.message & " Earlier branch updates from #variables.settings.remote# may still be in place." );
			}
			print.line().greenLine( "Created #flow.branch# from #flow.develop#." ).toConsole();
		}

		// 4. Update the version and release notes, then commit the files on this branch.
		if ( plan.bump ) {
			print.line().boldBlueLine( "=== Changing the version ===" ).toConsole();
			service( "VersionBumper" ).run(
				level = plan.level,
				preid = arguments.preid,
				quiet = true
			);
			release.commitVersion( plan.version, false );
		}

		// 5. Test the release branch before merging it anywhere.
		testReleaseBranch( flow, arguments.skipTests );

		// 6. Merge into develop first. If that merge fails, stop before merging into production.
		print.line().boldBlueLine( "=== Merging #flow.branch# ===" ).toConsole();
		mergeInto( flow.develop, flow );
		mergeInto( flow.production, flow );

		// 7. Publish from the production branch.
		publish( flow, release, plan.version, arguments.skipTests, arguments.skipHooks );

		// 8. Push both branches. Delete the release or hotfix branch unless keepBranch is true.
		finishBranches( flow, arguments.keepBranch );
	}

	// FIX A TAGGED FINISH

	/**
	 * Fixes a Gitflow finish that tagged a version without changing box.json, and publishes that
	 * version. GitKraken or git flow merged the branch and tagged production v1.0.1 while box.json
	 * still has 1.0.0. The remote does not have the tag yet.
	 *
	 * After the checks, this creates hotfix/1.0.1 (or release/1.1.0 for a minor or major version)
	 * from production and deletes the local tag. Then it runs the Gitflow release on that branch.
	 * That release changes the version, merges into develop and production, publishes, and tags
	 * the new merge commit. These are the manual steps from
	 * ReleaseService.checkFinishedWithoutVersion(), so a later failure leaves the same state and
	 * the same recovery steps.
	 *
	 * @finished The result of ReleaseService.finishedWithoutVersion(). canFix must be true.
	 * @options  The arguments of run().
	 */
	private function fixTaggedFinish( required struct finished, required struct options ){
		var tagName    = arguments.finished.tagName;
		var branch     = arguments.finished.branch;
		var production = variables.settings.branch;
		var level      = trim( arguments.finished.level & " " & arguments.finished.preid );

		if ( arguments.options.dryRun ) {
			print
				.line()
				.boldYellowLine( "PRACTICE RUN: Nothing will be changed, published, tagged, or pushed." )
				.line()
				.toConsole();
		}

		// 1. Check everything before the first change. The tag stays until the checks pass.
		print.boldBlueLine( "=== Checking before fixing tag #tagName# ===" ).toConsole();
		service( "ReleaseService" ).checkGitflowRelease(
			version      = arguments.finished.version,
			dryRun       = arguments.options.dryRun,
			requireNotes = true,
			replacesTag  = tagName
		);
		checkRemoteForFix( arguments.finished, arguments.options.dryRun );

		if ( arguments.options.dryRun ) {
			print
				.line()
				.boldYellowLine( "Practice run. These steps would run next:" )
				.line( "  git switch -c #branch# #production#" )
				.line( "  git tag -d #tagName#" )
				.line( "  box release gitflow #level#   (change the version, test, merge, publish, and push)" )
				.line()
				.yellowLine( "No package was built. The practice build would still see #tagName# on this commit." )
				.yellowLine( "Run the command without --dryRun to fix the tag and publish #arguments.finished.version#." )
				.toConsole();
			return;
		}

		// 2. Create the branch, then delete the tag. GitKraken can keep the finished branch. If it
		//    is merged into production, moving it to production loses no commits.
		print.line().boldBlueLine( "=== Fixing tag #tagName# ===" ).toConsole();
		try {
			repository().createBranch( branch, production, repository().branchExists( branch ) );
		} catch ( "Release.Git" exception ) {
			return stop( exception.message & " Nothing was changed." );
		}
		print.greenLine( "Created #branch# from #production#." ).toConsole();
		try {
			repository().deleteTag( tagName );
		} catch ( "Release.Git" exception ) {
			return fail(
				"#branch# was created, but tag #tagName# could not be deleted (#exception.detail#).",
				[ "git tag -d #tagName#", "box release gitflow #level#" ],
				"Run these commands to finish"
			);
		}
		print.greenLine( "Deleted the local tag #tagName#. The release tags the new merge commit." ).toConsole();

		// 3. Publish from the new branch, the same way as any hotfix or release branch.
		print.line().toConsole();
		return run(
			level      = arguments.finished.level,
			preid      = arguments.finished.preid,
			skipTests  = arguments.options.skipTests,
			keepBranch = arguments.options.keepBranch,
			skipHooks  = arguments.options.skipHooks
		);
	}

	/**
	 * Stops before the fix changes anything when the remote has commits that the tagged commit
	 * lacks. The release would add them to production, and the tag would no longer be on the
	 * current commit. A practice run checks the last fetched copy without fetching.
	 */
	private void function checkRemoteForFix( required struct finished, required boolean dryRun ){
		if ( !variables.settings.gitSync ) {
			return;
		}
		var repo       = repository();
		var remote     = variables.settings.remote;
		var production = variables.settings.branch;
		if ( !arguments.dryRun ) {
			try {
				repo.fetch();
			} catch ( "Release.Git" exception ) {
				var guidance = [ exception.detail ];
				var help     = host().remoteHelp( remote, exception.detail );
				if ( arrayLen( help ) ) {
					guidance.append( "" );
					guidance.append( help, true );
				}
				return fail( "git fetch failed. Nothing was changed.", guidance, "Git output" );
			}
		}

		if ( repo.remoteBranchExists( production ) && !repo.isAncestor( "refs/remotes/#remote#/#production#", "HEAD" ) ) {
			return fail(
				"#remote#/#production# has commits that are not in #arguments.finished.tagName#. Nothing was changed.",
				[
					"Someone added commits to #production# after the Gitflow finish. Check them before you publish #arguments.finished.version#:",
					"  git log HEAD..#remote#/#production#",
					"To publish them too, delete the tag, get the commits, and run the fix from #production#:",
					"  git tag -d #arguments.finished.tagName#",
					"  git pull #remote# #production#",
					"  git tag #arguments.finished.tagName#",
					"  box release publish --fixTag"
				]
			);
		}
		var branch = arguments.finished.branch;
		if ( repo.remoteBranchExists( branch ) && !repo.isAncestor( "refs/remotes/#remote#/#branch#", "HEAD" ) ) {
			return stop( "#remote#/#branch# has commits that are not on #production#. Nothing was changed. Merge or delete that branch, and then run the command again." );
		}
	}

	// BRANCHES AND VERSION

	/**
	 * Reads the branch names and identifies the current branch. The returned kind is "start"
	 * on develop, "release" on a release branch, or "hotfix" on a hotfix branch.
	 *
	 * @level The level the user gave. On production, the check for a tagged Gitflow finish uses it.
	 * @preid The prerelease label the user gave.
	 */
	private struct function resolveBranches( string level = "", string preid = "" ){
		var gitflow = repository().gitflowBranches();
		var flow    = {
			"production"    : variables.settings.branch,
			"develop"       : gitflow.develop,
			"releasePrefix" : gitflow.releasePrefix,
			"hotfixPrefix"  : gitflow.hotfixPrefix,
			"current"       : repository().currentBranch(),
			"kind"          : "",
			"branch"        : ""
		};

		if ( len( gitflow.production ) && gitflow.production != flow.production ) {
			return stop(
				"release.json uses production branch #flow.production#, but the Gitflow settings use #gitflow.production#. "
				& "Change ""branch"" in release.json or the Gitflow settings so they match."
			);
		}

		if ( flow.current == flow.develop ) {
			flow.kind = "start";
		} else if ( startsWith( flow.current, flow.releasePrefix ) ) {
			flow.kind   = "release";
			flow.branch = flow.current;
		} else if ( startsWith( flow.current, flow.hotfixPrefix ) ) {
			flow.kind   = "hotfix";
			flow.branch = flow.current;
		} else {
			// A Gitflow finish in GitKraken or git flow may have tagged a version without changing
			// box.json. Show how to publish that version instead of the general branch help.
			if ( flow.current == flow.production ) {
				service( "ReleaseService" ).checkFinishedWithoutVersion( arguments.level, arguments.preid );
			}
			return fail(
				"box release gitflow runs on #flow.develop#, a #flow.releasePrefix#* branch, or a #flow.hotfixPrefix#* branch. The current branch is #flow.current#.",
				[
					"On #flow.develop#:    box release gitflow minor   (creates a release branch, merges it, and publishes)",
					"On a release branch:  box release gitflow         (publishes the version in box.json if newer than production)",
					"On a hotfix branch:   box release gitflow         (publishes a patch, or the next prerelease if box.json has one, unless box.json is already newer than production)"
				]
			);
		}

		for ( var name in [ flow.production, flow.develop ] ) {
			if ( !repository().branchExists( name ) ) {
				return stop( "Branch #name# was not found on this computer. Create it or check it out from #variables.settings.remote# first." );
			}
		}
		return flow;
	}

	/**
	 * Chooses the release version. A level calculates a new version, except none keeps the
	 * current version. Without a level, use box.json's version if it is newer than production.
	 * Otherwise, ask the user for a level, except on a hotfix. A hotfix keeps a prerelease a
	 * prerelease: it uses prerelease when box.json has one and patch for other versions. Only
	 * a level the user gives can finish a prerelease. The returned note explains that choice.
	 */
	private struct function planVersion( required struct flow, string level = "", string preid = "" ){
		var current         = variables.config.version();
		var requested       = trim( arguments.level );
		var keepsPrerelease = false;

		if ( !len( requested ) ) {
			var released = releasedVersion( arguments.flow.production );
			if ( isNewer( current, released ) ) {
				return { "bump" : false, "level" : "", "version" : current, "note" : "" };
			}
			if ( arguments.flow.kind != "hotfix" ) {
				return fail(
					"Choose a version level. Version #current# is not newer than the version on #arguments.flow.production#.",
					[
						"box release gitflow patch   for bug fixes",
						"box release gitflow minor   for new features",
						"box release gitflow major   for breaking changes"
					],
					"Examples"
				);
			}
			keepsPrerelease = len( variables.versionService.parseVersion( current ).prerelease ) > 0;
			requested       = keepsPrerelease ? "prerelease" : "patch";
		}

		requested = service( "VersionBumper" ).ensureLevel( requested );
		if ( len( trim( arguments.preid ) ) && listFindNoCase( "major,minor,patch", requested ) ) {
			requested = "pre" & requested;
		}

		var next = current;
		var note = "";
		if ( requested != "none" ) {
			try {
				next = variables.versionService.nextVersion( current, requested, trim( arguments.preid ) );
				if ( keepsPrerelease ) {
					note = "box.json has prerelease #current#, so this hotfix publishes #next#. "
						& "To publish #variables.versionService.nextVersion( current, "patch" )# instead, run: box release gitflow patch";
				}
			} catch ( any exception ) {
				return stop( exception.message );
			}
		}
		return { "bump" : true, "level" : requested, "version" : next, "note" : note };
	}

	/**
	 * Reads production's box.json version from the last fetched copy of the remote branch first.
	 * The local production branch may contain a merge that an earlier run has not published yet.
	 * If the remote copy is missing, read the local branch. Return 0.0.0 if no version can be read.
	 */
	private string function releasedVersion( required string production ){
		for ( var ref in [ "refs/remotes/" & variables.settings.remote & "/" & arguments.production, "refs/heads/" & arguments.production ] ) {
			var packageText = repository().fileAt( ref, "box.json" );
			if ( len( packageText ) ) {
				try {
					return deserializeJSON( packageText ).version ?: "0.0.0";
				} catch ( any ignoredException ) {
					return "0.0.0";
				}
			}
		}
		return "0.0.0";
	}

	/** Returns true when first is newer than second. Returns false if either version is invalid. */
	private boolean function isNewer( required string first, required string second ){
		try {
			return variables.versionService.compareVersions( arguments.first, arguments.second ) > 0;
		} catch ( any ignoredException ) {
			return false;
		}
	}

	/**
	 * Checks for existing release branches before starting another release. A hotfix can be
	 * published while a release branch exists. The user must also merge the fix into that branch.
	 */
	private void function checkBranches( required struct flow ){
		var openReleases = repository().branchesWithPrefix( arguments.flow.releasePrefix );
		if ( arguments.flow.kind == "start" ) {
			if ( repository().branchExists( arguments.flow.branch ) || repository().remoteBranchExists( arguments.flow.branch ) ) {
				return fail(
					"#arguments.flow.branch# already exists. Nothing was changed.",
					[ "git switch #arguments.flow.branch#", "box release gitflow" ],
					"Publish the existing release branch instead"
				);
			}
			if ( arrayLen( openReleases ) ) {
				return fail(
					"Release branch #openReleases[ 1 ]# is still open. Merge and publish it, or delete it, before starting another release.",
					[ "git switch #openReleases[ 1 ]#", "box release gitflow" ],
					"Publish the existing release branch"
				);
			}
			print.greenLine( "  ok  no release branch is open" ).toConsole();
		} else if ( arguments.flow.kind == "hotfix" && arrayLen( openReleases ) ) {
			print
				.yellowLine( "  note  Release branch #openReleases[ 1 ]# is open. It also needs the hotfix." )
				.yellowLine( "        This command merges #arguments.flow.branch# into #arguments.flow.develop# and #arguments.flow.production#. After publishing, merge #arguments.flow.production# into #openReleases[ 1 ]# yourself to include the fix." )
				.toConsole();
		}
	}

	// RELEASE STEPS

	/**
	 * Gets commits from the remote and updates production, develop, and the release or hotfix branch.
	 * Each branch update is a fast-forward: it adds the remote's commits without a merge commit.
	 * Stop if a local branch and the remote both have commits that the other does not have.
	 */
	private void function syncBranches( required struct flow ){
		print.line().boldBlueLine( "=== Updating from #variables.settings.remote# ===" ).toConsole();
		try {
			repository().fetch();
		} catch ( "Release.Git" exception ) {
			var guidance = [ exception.detail ];
			var help     = host().remoteHelp( variables.settings.remote, exception.detail );
			if ( arrayLen( help ) ) {
				guidance.append( "" );
				guidance.append( help, true );
			}
			return fail( "git fetch failed. Nothing was published or pushed.", guidance, "Git output" );
		}

		var before = repository().headCommit();
		var names  = [ arguments.flow.production, arguments.flow.develop ];
		if ( arguments.flow.kind != "start" ) {
			names.append( arguments.flow.branch );
		}
		for ( var name in names ) {
			fastForward( name, arguments.flow.current );
		}
		if ( repository().headCommit() != before ) {
			return stop(
				"The #variables.settings.remote# remote had new commits for #arguments.flow.current#, and that branch is now updated. Other branches may also have been updated. Nothing was published or pushed. "
				& "Run the command again to check the updated project."
			);
		}
		print.greenLine( "Branch updates from #variables.settings.remote# are complete." ).toConsole();
	}

	/**
	 * Adds the remote's commits when the local branch has no extra commits of its own. Leave the
	 * local branch unchanged if it already contains the remote's commits or has no copy on the remote.
	 */
	private void function fastForward( required string name, required string current ){
		var outcome = repository().fastForward( arguments.name, arguments.current );
		if ( outcome == "diverged" ) {
			return fail(
				"#arguments.name# and #variables.settings.remote#/#arguments.name# both have new commits. This branch was not updated. Earlier branch updates may still be in place.",
				[ "git switch #arguments.name#", "git pull #variables.settings.remote# #arguments.name#", "Resolve any conflicts and commit the merge. Switch back to #arguments.current#. Then run box release gitflow again." ],
				"Merge the local and remote commits first"
			);
		}
		if ( outcome == "updated" ) {
			print.line( "Updated #arguments.name# from #variables.settings.remote#." ).toConsole();
		}
	}

	/** Runs enabled tests on the release or hotfix branch. A test failure stops before merging. */
	private void function testReleaseBranch( required struct flow, required boolean skipTests ){
		if ( arguments.skipTests || !variables.settings.runTests ) {
			return;
		}
		print.line().boldBlueLine( "=== Testing #arguments.flow.branch# ===" ).toConsole();
		try {
			service( "TestRunner" ).runOnce();
		} catch ( any exception ) {
			if ( left( exception.type ?: "", 8 ) != "Release." ) {
				rethrow;
			}
			print.redLine( exception.message ).toConsole();
			return fail(
				"The tests did not pass on #arguments.flow.branch#. Nothing was merged or pushed.",
				[ "Fix the problem on #arguments.flow.branch# and commit it.", "Then run: box release gitflow" ]
			);
		}
		print.greenLine( "The tests passed on #arguments.flow.branch#." ).toConsole();
	}

	/**
	 * Merges the release or hotfix branch into the target with a merge commit. Git does nothing
	 * if the target already contains that branch's commits.
	 *
	 * When the changelog is the only file with conflicts, this combines both versions and
	 * commits the merge. Any other conflict cancels the merge. Then try to switch back to the
	 * release or hotfix branch and show the manual steps.
	 *
	 * The branch may release notes that were already under [Unreleased] where both branches
	 * started, while the target added notes of its own. Then this always combines the changelog,
	 * even when Git reports no conflict. Git could otherwise put the target's new notes inside
	 * the released version. See ChangelogService.withoutReleasedNotes().
	 */
	private void function mergeInto( required string target, required struct flow ){
		var repo = repository();
		repo.switchTo( arguments.target );

		var released = releasedNotes( arguments.flow );
		var outcome  = {};
		try {
			outcome = repo.tryMerge( arguments.flow.branch, arrayLen( released.notes ) > 0 );
		} catch ( "Release.Git" exception ) {
			return mergeFailed( arguments.target, arguments.flow, [ "Git output: " & exception.detail ] );
		}

		if ( !outcome.merged || arrayLen( released.notes ) ) {
			var reason = "";
			try {
				reason = resolveChangelogConflict( arguments.target, arguments.flow, outcome, released );
			} catch ( any exception ) {
				repo.abortMerge();
				rethrow;
			}
			if ( len( reason ) ) {
				try {
					repo.abortMerge();
				} catch ( "Release.Git" exception ) {
					return stop( exception.message );
				}
				return mergeFailed( arguments.target, arguments.flow, [ reason, "", "Git output: " & outcome.output ] );
			}
		}
		print.greenLine( "Merged #arguments.flow.branch# into #arguments.target#." ).toConsole();
	}

	/**
	 * Returns the changelogs for a merge into the current branch when the branch releases notes
	 * that were already under [Unreleased] where both branches started. Returns
	 * { base, ours, theirs, notes }. notes is empty when the merge needs no extra step.
	 */
	private struct function releasedNotes( required struct flow ){
		var none      = { "base" : "", "ours" : "", "theirs" : "", "notes" : [] };
		var repo      = repository();
		var changelog = variables.settings.changelog;
		var path      = variables.config.repoPath( changelog );
		if ( !fileExists( path ) || repo.isAncestor( arguments.flow.branch, "HEAD" ) ) {
			return none;
		}
		var baseCommit = repo.mergeBase( arguments.flow.branch );
		if ( !len( baseCommit ) ) {
			return none;
		}
		var base   = repo.fileAt( baseCommit, changelog );
		var theirs = repo.fileAt( arguments.flow.branch, changelog );
		if ( !len( base ) || !len( theirs ) ) {
			return none;
		}
		var prepared = variables.changelogService.withoutReleasedNotes(
			base          = base,
			ours          = fileRead( path ),
			theirs        = theirs,
			changelogName = changelog
		);
		prepared.theirs = theirs;
		return prepared;
	}

	/**
	 * Combines the changelog when it is the only file with conflicts, then commits the merge.
	 * Returns an empty string on success. Otherwise, it returns the reason the merge needs a
	 * person, and the caller cancels the merge.
	 *
	 * @released The result of releasedNotes(). When it has notes, the merge stopped before its
	 *           commit, and this combines the prepared changelogs even without a conflict.
	 */
	private string function resolveChangelogConflict(
		required string target,
		required struct flow,
		required struct outcome,
		required struct released
	){
		var repo      = repository();
		var changelog = variables.settings.changelog;
		var conflicts = arguments.outcome.conflicts;
		var prepared  = arrayLen( arguments.released.notes ) > 0;
		if ( arrayLen( conflicts ) > 1 || ( arrayLen( conflicts ) == 1 && compare( conflicts[ 1 ], repo.fullName( changelog ) ) != 0 ) ) {
			return "These files have conflicts: #arrayToList( conflicts, ", " )#";
		}

		var merged   = "";
		var versions = {};
		try {
			versions = prepared
				? { "base" : arguments.released.base, "ours" : arguments.released.ours, "theirs" : arguments.released.theirs }
				: repo.conflictVersions( changelog );
			merged   = variables.changelogService.mergeChangelogs(
				base          = versions.base,
				ours          = versions.ours,
				theirs        = versions.theirs,
				changelogName = changelog
			);
		} catch ( "Release.Changelog.MergeConflict" exception ) {
			return exception.message;
		} catch ( "Release.Git" exception ) {
			return exception.message;
		}

		fileWrite( variables.config.repoPath( changelog ), merged );
		repo.completeMerge( [ changelog ] );

		var added    = [];
		var labels   = [];
		var ours     = variables.changelogService.versionHeadings( versions.ours );
		for ( var version in variables.changelogService.versionHeadings( versions.theirs ) ) {
			if ( !arrayFindNoCase( ours, version ) ) {
				added.append( version );
				labels.append( "[#version#]" );
			}
		}
		var summary = "Combined #changelog#: kept the [Unreleased] notes on #arguments.target#";
		if ( prepared ) {
			var count = arrayLen( arguments.released.notes );
			summary &= ", removed #count# note#( count == 1 ? "" : "s" )# that #arrayLen( labels ) ? arrayToList( labels, ", " ) : "this release"# released,";
		}
		summary &= arrayLen( labels ) ? " and added #arrayToList( labels, ", " )#." : ".";
		print.greenLine( summary ).toConsole();

		var repeated = variables.changelogService.repeatedNotes( merged, added );
		if ( arrayLen( repeated ) ) {
			print
				.yellowLine( "  warning  #arguments.target# still lists these notes under [Unreleased], and the new section has them too:" )
				.toConsole();
			for ( var note in repeated ) {
				print.yellowLine( "           - #note#" ).toConsole();
			}
		}
		return "";
	}

	/** Switches back to the release or hotfix branch and stops with the manual merge steps. */
	private void function mergeFailed( required string target, required struct flow, required array detail ){
		try {
			repository().switchTo( arguments.flow.branch );
		} catch ( "Release.Git" ignoredException ) {
			// The instructions below include the switch command.
		}
		var steps = [
			"Merge #arguments.flow.branch# into #arguments.target# and fix the conflicts:",
			"  git switch #arguments.target#",
			"  git merge --no-ff #arguments.flow.branch#",
			"Commit the resolved merge. Then return to the release or hotfix branch and publish:",
			"  git switch #arguments.flow.branch#",
			"  box release gitflow",
			""
		];
		steps.append( arguments.detail, true );
		return fail(
			"#arguments.flow.branch# could not be merged into #arguments.target#. Nothing was pushed.",
			steps,
			"Merge conflict"
		);
	}

	/**
	 * Publishes from production. If tests passed on the release or hotfix branch and production
	 * has the same files, skip the second test run. Otherwise, run enabled tests during the build.
	 */
	private void function publish(
		required struct flow,
		required any release,
		required string version,
		required boolean skipTests,
		boolean skipHooks = false
	){
		var sameFiles = repository().treeOf( arguments.flow.production ) == repository().treeOf( arguments.flow.branch );
		var testedOn  = ( variables.settings.runTests && sameFiles && !arguments.skipTests ) ? arguments.flow.branch : "";

		try {
			arguments.release.run(
				skipTests = arguments.skipTests,
				testedOn  = testedOn,
				sync      = false,
				skipHooks = arguments.skipHooks
			);
		} catch ( any exception ) {
			var tagName = variables.settings.tagPrefix & arguments.version;
			if (
				arguments.release.hasPublished()
				|| repository().localTag( tagName ) != "missing"
				|| left( exception.type ?: "", 8 ) != "Release."
			) {
				rethrow;
			}
			print.line().redLine( exception.message ).toConsole();
			return fail(
				trim( "Version #arguments.version# is merged on this computer, and nothing was published or pushed. " & arguments.release.hookNote() ),
				[ "Switch back to #arguments.flow.branch# and fix the problem. Commit any code changes. Then run box release gitflow without a level:", "  git switch #arguments.flow.branch#", "  box release gitflow" ]
			);
		}
	}

	/**
	 * Pushes production and develop, then switches to develop. Delete the release or hotfix
	 * branch unless keepBranch is true. Push or delete failures print warnings because publishing
	 * is already complete. A failure to switch branches still stops the command.
	 */
	private void function finishBranches( required struct flow, required boolean keepBranch ){
		print.line().boldBlueLine( "=== Finishing #arguments.flow.branch# ===" ).toConsole();

		try {
			repository().push( [ arguments.flow.production, arguments.flow.develop ] );
			print.greenLine( "Pushed #arguments.flow.production# and #arguments.flow.develop# to #variables.settings.remote#." ).toConsole();
		} catch ( "Release.Git" exception ) {
			print
				.yellowLine( "  warning  The branches could not be pushed (#exception.detail#)." )
				.yellowLine( "           Run: git push #variables.settings.remote# #arguments.flow.production# #arguments.flow.develop#" )
				.toConsole();
		}

		repository().switchTo( arguments.flow.develop );
		if ( !arguments.keepBranch ) {
			deleteReleaseBranch( arguments.flow );
		}
		print
			.line()
			.boldGreenLine( "Finished #arguments.flow.branch#. You are on #arguments.flow.develop#." )
			.toConsole();
	}

	/**
	 * Deletes the release or hotfix branch locally and on the remote. First, check that develop and
	 * production both contain all its commits. Then use git branch -D to delete the local branch.
	 * git branch -d can refuse to delete it when its tracked branch on the remote is behind.
	 */
	private void function deleteReleaseBranch( required struct flow ){
		var branch = arguments.flow.branch;
		var repo   = repository();
		if ( !repo.isAncestor( branch, arguments.flow.develop ) || !repo.isAncestor( branch, arguments.flow.production ) ) {
			print.yellowLine( "  warning  #branch# has commits that are not merged, so it was not deleted." ).toConsole();
			return;
		}

		try {
			repo.deleteBranch( branch );
			print.greenLine( "Deleted #branch#." ).toConsole();
		} catch ( "Release.Git" exception ) {
			print.yellowLine( "  warning  #branch# could not be deleted (#exception.detail#)." ).toConsole();
		}

		try {
			if ( repo.deleteRemoteBranch( branch ) ) {
				print.greenLine( "Deleted #branch# on #variables.settings.remote#." ).toConsole();
			}
		} catch ( "Release.Git" exception ) {
			print
				.yellowLine( "  warning  #branch# could not be deleted on #variables.settings.remote# (#exception.detail#)." )
				.yellowLine( "           Run: git push #variables.settings.remote# --delete #branch#" )
				.toConsole();
		}
	}

	/**
	 * Shows the planned release steps, then builds from the current branch. The build writes
	 * temporary files and the package zip. Publishing and Git changes are only shown.
	 */
	private function practice(
		required struct flow,
		required struct plan,
		required any release,
		required string preid,
		required boolean skipTests,
		required boolean keepBranch,
		boolean skipHooks = false
	){
		var flow  = arguments.flow;
		var steps = print.line().boldYellowLine( "Practice run. These steps would run next:" );
		if ( variables.settings.gitSync ) {
			// Pad the command so its note lines up with the publish step's note.
			var fetchStep = "git fetch " & variables.settings.remote;
			steps.line(
				"  " & fetchStep & repeatString( " ", max( 1, 27 - len( fetchStep ) ) )
				& "(update #flow.production#, #flow.develop#, and any existing release or hotfix branch without merge commits)"
			);
		}
		if ( flow.kind == "start" ) {
			steps.line( "  git switch -c #flow.branch# #flow.develop#" );
		}
		if ( arguments.plan.bump ) {
			steps
				.line( "  box release bump #arguments.plan.level#" )
				.line( "  git commit -m ""Release #arguments.plan.version#""" );
		}
		if ( !arguments.skipTests && variables.settings.runTests ) {
			steps.line( "  run the tests on #flow.branch#" );
		}
		steps
			.line( "  git switch #flow.develop#" )
			.line( "  git merge --no-ff #flow.branch#" )
			.line( "  git switch #flow.production#" )
			.line( "  git merge --no-ff #flow.branch#" )
			.line( "  box release publish        (build, publish, tag, and push)" )
			.line( "  git push #variables.settings.remote# #flow.production# #flow.develop#" )
			.line( "  git switch #flow.develop#" );
		if ( !arguments.keepBranch ) {
			steps.line( "  git branch -D #flow.branch#  (after checking both merges; also delete it on #variables.settings.remote#)" );
		}
		steps.toConsole();

		if ( arguments.plan.bump ) {
			service( "VersionBumper" ).run(
				level  = arguments.plan.level,
				preid  = arguments.preid,
				dryRun = true,
				quiet  = true
			);
			arguments.release.previewVersion( arguments.plan.version );
		}

		print
			.line()
			.line( "The practice build uses the files on #flow.current#. A real run builds #flow.production# after the merges." )
			.line()
			.toConsole();
		return arguments.release.run(
			dryRun    = true,
			skipTests = arguments.skipTests,
			sync      = false,
			version   = arguments.plan.version,
			skipHooks = arguments.skipHooks
		);
	}

	// TEXT HELPERS

	private boolean function startsWith( required string text, required string prefix ){
		return len( arguments.prefix ) && left( arguments.text, len( arguments.prefix ) ) == arguments.prefix;
	}
}
