/**
 * Finishes a Gitflow release or hotfix and publishes it. This is `box release gitflow`.
 *
 * On develop, it first creates a release branch, such as release/1.2.0. On a release or hotfix
 * branch, it finishes that branch. To finish, it changes the version when needed, runs the
 * tests on the branch, and merges the branch into develop and the production branch.
 * ReleaseService then publishes from the production branch. Last, this component pushes both
 * branches and deletes the release branch.
 *
 * The merges happen on this computer. Nothing is pushed until the build passes. If a step
 * fails before publishing, run the command again on the release branch. The finished merges
 * are skipped.
 *
 * Branch names come from the Gitflow settings in Git config. GitKraken and git flow both store
 * them there. The production branch comes from release.json.
 */
component extends="commandbox-release.models.BaseService" {

	property name="versionService" inject="VersionService@commandbox-release";

	/**
	 * Starts or finishes a Gitflow release and publishes it.
	 *
	 * @level      The version change. Required on develop. On a hotfix branch, patch is the
	 *             default. Leave it out when the branch already has the new version.
	 * @preid      A prerelease label. For example, minor with beta starts 1.1.0-beta.1.
	 * @dryRun     Shows the steps and builds the package without changing branches or files.
	 * @skipTests  Skips the tests.
	 * @keepBranch Keeps the release or hotfix branch after the release.
	 */
	function run(
		string level       = "",
		string preid       = "",
		boolean dryRun     = false,
		boolean skipTests  = false,
		boolean keepBranch = false
	){
		var flow = resolveBranches();
		var plan = planVersion( flow, arguments.level, arguments.preid );
		if ( flow.kind == "start" ) {
			flow.branch = flow.releasePrefix & plan.version;
		}

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "PRACTICE RUN: No branches or files will be changed, and nothing will be published or pushed." )
				.line()
				.toConsole();
		}

		// 1. Check everything before changing branches or files.
		print.boldBlueLine( "=== Checking before the Gitflow release ===" ).toConsole();
		var release = service( "ReleaseService" );
		release.checkGitflowRelease(
			version      = plan.version,
			dryRun       = arguments.dryRun,
			requireNotes = plan.bump
		);
		checkBranches( flow );

		if ( arguments.dryRun ) {
			return practice( flow, plan, release, arguments.preid, arguments.skipTests, arguments.keepBranch );
		}

		// 2. Get new commits. Stop if the current branch changed, because the checks used the
		//    old files.
		if ( variables.settings.gitSync ) {
			syncBranches( flow );
		}

		// 3. Create the release branch from develop.
		if ( flow.kind == "start" ) {
			var created = git( [ "switch", "-c", flow.branch, flow.develop ] );
			if ( created.exitCode != 0 ) {
				return stop( "#flow.branch# could not be created (#created.output#). Nothing was changed." );
			}
			print.line().greenLine( "Created #flow.branch# from #flow.develop#." ).toConsole();
		}

		// 4. Change the version and commit it on the release branch.
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

		// 6. Merge into develop first. A conflict there is the most likely, and then the
		//    production branch is not changed yet.
		print.line().boldBlueLine( "=== Merging #flow.branch# ===" ).toConsole();
		mergeInto( flow.develop, flow );
		mergeInto( flow.production, flow );

		// 7. Publish from the production branch.
		publish( flow, release, plan.version, arguments.skipTests );

		// 8. Push both branches and delete the release branch.
		finishBranches( flow, arguments.keepBranch );
	}

	// BRANCHES AND VERSION

	/**
	 * Reads the Gitflow branch names and decides what to do on the current branch.
	 * The result has kind "start" (on develop), "release", or "hotfix".
	 */
	private struct function resolveBranches(){
		var flow = {
			"production"    : variables.settings.branch,
			"develop"       : gitConfig( "gitflow.branch.develop", "develop" ),
			"releasePrefix" : gitConfig( "gitflow.prefix.release", "release/" ),
			"hotfixPrefix"  : gitConfig( "gitflow.prefix.hotfix", "hotfix/" ),
			"current"       : currentBranch(),
			"kind"          : "",
			"branch"        : ""
		};

		var gitflowProduction = gitConfig( "gitflow.branch.master", "" );
		if ( len( gitflowProduction ) && gitflowProduction != flow.production ) {
			return stop(
				"release.json uses production branch #flow.production#, but the Gitflow settings use #gitflowProduction#. "
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
			return fail(
				"box release gitflow runs on #flow.develop#, a #flow.releasePrefix#* branch, or a #flow.hotfixPrefix#* branch. The current branch is #flow.current#.",
				[
					"On #flow.develop#:    box release gitflow minor   (creates the release branch and finishes it)",
					"On a release branch:  box release gitflow         (finishes it)",
					"On a hotfix branch:   box release gitflow         (finishes it as a patch)"
				]
			);
		}

		for ( var name in [ flow.production, flow.develop ] ) {
			if ( !branchExists( name ) ) {
				return stop( "Branch #name# was not found on this computer. Create it or check it out from origin first." );
			}
		}
		return flow;
	}

	/**
	 * Decides the version to release. A level always changes the version. Without a level, the
	 * command uses box.json when its version is newer than the production branch. A hotfix
	 * uses patch otherwise.
	 */
	private struct function planVersion( required struct flow, string level = "", string preid = "" ){
		var current   = variables.config.version();
		var requested = trim( arguments.level );

		if ( !len( requested ) ) {
			var released = releasedVersion( arguments.flow.production );
			if ( isNewer( current, released ) ) {
				return { "bump" : false, "level" : "", "version" : current };
			}
			if ( arguments.flow.kind != "hotfix" ) {
				return fail(
					"Choose a version level. Version #current# was already released from #arguments.flow.production#.",
					[
						"box release gitflow patch   for bug fixes",
						"box release gitflow minor   for new features",
						"box release gitflow major   for breaking changes"
					],
					"Examples"
				);
			}
			requested = "patch";
		}

		requested = service( "VersionBumper" ).ensureLevel( requested );
		if ( len( trim( arguments.preid ) ) && listFindNoCase( "major,minor,patch", requested ) ) {
			requested = "pre" & requested;
		}

		var next = current;
		if ( requested != "none" ) {
			try {
				next = variables.versionService.nextVersion( current, requested, trim( arguments.preid ) );
			} catch ( any exception ) {
				return stop( exception.message );
			}
		}
		return { "bump" : true, "level" : requested, "version" : next };
	}

	/**
	 * Returns the box.json version on the production branch. It prefers origin's copy, because
	 * the local branch may already have an unpublished merge from an earlier run.
	 */
	private string function releasedVersion( required string production ){
		for ( var ref in [ "refs/remotes/origin/" & arguments.production, "refs/heads/" & arguments.production ] ) {
			var shown = git( [ "show", ref & ":./box.json" ] );
			if ( shown.exitCode == 0 ) {
				try {
					return deserializeJSON( shown.output ).version ?: "0.0.0";
				} catch ( any ignoredException ) {
					return "0.0.0";
				}
			}
		}
		return "0.0.0";
	}

	/** Returns true when the first version is higher. An invalid version is never higher. */
	private boolean function isNewer( required string first, required string second ){
		try {
			return variables.versionService.compareVersions( arguments.first, arguments.second ) > 0;
		} catch ( any ignoredException ) {
			return false;
		}
	}

	/**
	 * Checks the release branch before any change. Gitflow allows one release branch at a time.
	 * A hotfix finishes while a release branch is open, but that branch also needs the fix.
	 */
	private void function checkBranches( required struct flow ){
		var openReleases = branchesWithPrefix( arguments.flow.releasePrefix );
		if ( arguments.flow.kind == "start" ) {
			if ( branchExists( arguments.flow.branch ) || remoteBranchExists( arguments.flow.branch ) ) {
				return fail(
					"#arguments.flow.branch# already exists. Nothing was changed.",
					[ "git switch #arguments.flow.branch#", "box release gitflow" ],
					"Finish that branch instead"
				);
			}
			if ( arrayLen( openReleases ) ) {
				return fail(
					"Release branch #openReleases[ 1 ]# is still open. Finish or delete it first.",
					[ "git switch #openReleases[ 1 ]#", "box release gitflow" ],
					"Finish that branch"
				);
			}
			print.greenLine( "  ok  no release branch is open" ).toConsole();
		} else if ( arguments.flow.kind == "hotfix" && arrayLen( openReleases ) ) {
			print
				.yellowLine( "  note  Release branch #openReleases[ 1 ]# is open. Gitflow also merges a hotfix into it." )
				.yellowLine( "        This command merges into #arguments.flow.develop# only. Merge #arguments.flow.branch# into #openReleases[ 1 ]# yourself." )
				.toConsole();
		}
	}

	// RELEASE STEPS

	/**
	 * Fast-forwards the production branch, develop, and the release branch from origin. It
	 * stops when a local branch and origin both have new commits.
	 */
	private void function syncBranches( required struct flow ){
		print.line().boldBlueLine( "=== Updating from origin ===" ).toConsole();
		var fetched = git( [ "fetch", "origin" ] );
		if ( fetched.exitCode != 0 ) {
			return fail( "git fetch failed. Nothing was changed.", [ fetched.output ], "Git output" );
		}

		var before = headCommit();
		var names  = [ arguments.flow.production, arguments.flow.develop ];
		if ( arguments.flow.kind != "start" ) {
			names.append( arguments.flow.branch );
		}
		for ( var name in names ) {
			fastForward( name, arguments.flow.current );
		}
		if ( headCommit() != before ) {
			return stop(
				"Origin had new commits for #arguments.flow.current#, and they are now in this checkout. Nothing else was changed. "
				& "Run the command again to check the updated project."
			);
		}
		print.greenLine( "Up to date with origin." ).toConsole();
	}

	/**
	 * Moves one local branch to origin's commit when the local branch is only behind. A branch
	 * that is ahead or missing on origin stays as it is.
	 */
	private void function fastForward( required string name, required string current ){
		var remote = git( [ "rev-parse", "-q", "--verify", "refs/remotes/origin/" & arguments.name ] );
		if ( remote.exitCode != 0 ) {
			return;
		}
		var remoteCommit = trim( remote.output );
		var localCommit  = trim( git( [ "rev-parse", "refs/heads/" & arguments.name ] ).output );
		if ( localCommit == remoteCommit || isAncestor( remoteCommit, localCommit ) ) {
			return;
		}
		if ( !isAncestor( localCommit, remoteCommit ) ) {
			return fail(
				"#arguments.name# and origin/#arguments.name# both have new commits. Nothing was changed.",
				[ "git switch #arguments.name#", "git pull origin #arguments.name#", "Then run box release gitflow again." ],
				"Combine them first"
			);
		}

		var updated = arguments.name == arguments.current
			? git( [ "merge", "--ff-only", "origin/" & arguments.name ] )
			: git( [ "update-ref", "refs/heads/" & arguments.name, remoteCommit, localCommit ] );
		if ( updated.exitCode != 0 ) {
			return stop( "#arguments.name# could not be updated from origin (#updated.output#)." );
		}
		print.line( "Updated #arguments.name# from origin." ).toConsole();
	}

	/** Runs the tests on the release branch. A failure stops before any merge. */
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
	 * Merges the release branch into one branch with a merge commit. It skips a merge that is
	 * already done. On a conflict, it cancels the merge and returns to the release branch.
	 */
	private void function mergeInto( required string target, required struct flow ){
		switchTo( arguments.target );
		var merged = git( [ "merge", "--no-ff", "--no-edit", arguments.flow.branch ] );
		if ( merged.exitCode != 0 ) {
			git( [ "merge", "--abort" ] );
			git( [ "switch", arguments.flow.branch ] );
			return fail(
				"#arguments.flow.branch# could not be merged into #arguments.target#. Nothing was pushed.",
				[
					"Merge it yourself and fix the conflicts:",
					"  git switch #arguments.target#",
					"  git merge --no-ff #arguments.flow.branch#",
					"Then finish the release:",
					"  git switch #arguments.flow.branch#",
					"  box release gitflow",
					"",
					"Git output: " & merged.output
				],
				"Merge conflict"
			);
		}
		print.greenLine( "Merged #arguments.flow.branch# into #arguments.target#." ).toConsole();
	}

	/**
	 * Publishes from the production branch. The tests already ran on the release branch. The
	 * build skips them when the production branch has the same files.
	 */
	private void function publish(
		required struct flow,
		required any release,
		required string version,
		required boolean skipTests
	){
		var sameFiles  = treeOf( arguments.flow.production ) == treeOf( arguments.flow.branch );
		var buildSkips = arguments.skipTests || ( variables.settings.runTests && sameFiles );
		if ( variables.settings.runTests && sameFiles && !arguments.skipTests ) {
			print.line().line( "The tests passed on #arguments.flow.branch#. The build does not run them again." ).toConsole();
		}

		try {
			arguments.release.run( skipTests = buildSkips, sync = false );
		} catch ( any exception ) {
			var tagName = variables.settings.tagPrefix & arguments.version;
			if (
				arguments.release.hasPublished()
				|| tagExists( tagName )
				|| left( exception.type ?: "", 8 ) != "Release."
			) {
				rethrow;
			}
			print.line().redLine( exception.message ).toConsole();
			return fail(
				"Version #arguments.version# is merged on this computer, and nothing was published or pushed.",
				[ "Fix the problem. Then finish the release again:", "  git switch #arguments.flow.branch#", "  box release gitflow" ]
			);
		}
	}

	/**
	 * Pushes the production branch and develop. Then it deletes the release branch. The release
	 * is already published, so a failure here prints a warning instead of stopping.
	 */
	private void function finishBranches( required struct flow, required boolean keepBranch ){
		print.line().boldBlueLine( "=== Finishing #arguments.flow.branch# ===" ).toConsole();

		var pushed = git( [ "push", "origin", arguments.flow.production, arguments.flow.develop ] );
		if ( pushed.exitCode == 0 ) {
			print.greenLine( "Pushed #arguments.flow.production# and #arguments.flow.develop# to origin." ).toConsole();
		} else {
			print
				.yellowLine( "  warning  The branches could not be pushed (#pushed.output#)." )
				.yellowLine( "           Run: git push origin #arguments.flow.production# #arguments.flow.develop#" )
				.toConsole();
		}

		switchTo( arguments.flow.develop );
		if ( !arguments.keepBranch ) {
			deleteReleaseBranch( arguments.flow );
		}
		print
			.line()
			.boldGreenLine( "Finished #arguments.flow.branch#. You are on #arguments.flow.develop#." )
			.toConsole();
	}

	/**
	 * Deletes the release branch on this computer and on origin. It first checks that develop
	 * and the production branch contain the branch. git branch -d is not enough, because it
	 * also refuses when origin's copy of the branch is older.
	 */
	private void function deleteReleaseBranch( required struct flow ){
		var branch = arguments.flow.branch;
		if ( !isAncestor( branch, arguments.flow.develop ) || !isAncestor( branch, arguments.flow.production ) ) {
			print.yellowLine( "  warning  #branch# has commits that are not merged, so it was not deleted." ).toConsole();
			return;
		}

		var deleted = git( [ "branch", "-D", branch ] );
		if ( deleted.exitCode == 0 ) {
			print.greenLine( "Deleted #branch#." ).toConsole();
		} else {
			print.yellowLine( "  warning  #branch# could not be deleted (#deleted.output#)." ).toConsole();
		}

		var onOrigin = git( [ "ls-remote", "--exit-code", "--heads", "origin", "refs/heads/" & branch ] );
		if ( onOrigin.exitCode != 0 ) {
			return;
		}
		var remoteDeleted = git( [ "push", "origin", "--delete", branch ] );
		if ( remoteDeleted.exitCode == 0 ) {
			print.greenLine( "Deleted #branch# on origin." ).toConsole();
		} else {
			print
				.yellowLine( "  warning  #branch# could not be deleted on origin (#remoteDeleted.output#)." )
				.yellowLine( "           Run: git push origin --delete #branch#" )
				.toConsole();
		}
	}

	/**
	 * Shows the steps of a real run. Then it runs the practice build and publish from the
	 * current branch.
	 */
	private function practice(
		required struct flow,
		required struct plan,
		required any release,
		required string preid,
		required boolean skipTests,
		required boolean keepBranch
	){
		var flow  = arguments.flow;
		var steps = print.line().boldYellowLine( "Practice run. These steps would run next:" );
		if ( variables.settings.gitSync ) {
			steps.line( "  git fetch origin           (and fast-forward #flow.production# and #flow.develop#)" );
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
			.line( "  git push origin #flow.production# #flow.develop#" )
			.line( "  git switch #flow.develop#" );
		if ( !arguments.keepBranch ) {
			steps.line( "  git branch -d #flow.branch#  (and delete it on origin)" );
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
			version   = arguments.plan.version
		);
	}

	// GIT HELPERS

	private struct function git( required array args ){
		return variables.config.execNative( "git", arguments.args );
	}

	/** Returns a Git config value, or the default when it is missing or empty. */
	private string function gitConfig( required string key, required string defaultValue ){
		var result = git( [ "config", "--get", arguments.key ] );
		return result.exitCode == 0 && len( trim( result.output ) ) ? trim( result.output ) : arguments.defaultValue;
	}

	private string function currentBranch(){
		var branch = git( [ "rev-parse", "--abbrev-ref", "HEAD" ] );
		if ( branch.exitCode != 0 ) {
			return stop( "Git could not identify the current branch (#branch.output#). Check that this is a Git repository." );
		}
		return trim( branch.output );
	}

	private string function headCommit(){
		return trim( git( [ "rev-parse", "HEAD" ] ).output );
	}

	/** Returns the file tree ID of a branch. Two branches with the same ID have the same files. */
	private string function treeOf( required string branch ){
		return trim( git( [ "rev-parse", arguments.branch & "^{tree}" ] ).output );
	}

	private void function switchTo( required string branch ){
		var switched = git( [ "switch", arguments.branch ] );
		if ( switched.exitCode != 0 ) {
			return stop( "Git could not switch to #arguments.branch# (#switched.output#)." );
		}
	}

	private boolean function branchExists( required string branch ){
		return git( [ "rev-parse", "-q", "--verify", "refs/heads/" & arguments.branch ] ).exitCode == 0;
	}

	private boolean function remoteBranchExists( required string branch ){
		return git( [ "rev-parse", "-q", "--verify", "refs/remotes/origin/" & arguments.branch ] ).exitCode == 0;
	}

	private boolean function tagExists( required string tagName ){
		return git( [ "rev-parse", "-q", "--verify", "refs/tags/" & arguments.tagName ] ).exitCode == 0;
	}

	/** Returns true when the first commit is in the history of the second commit. */
	private boolean function isAncestor( required string ancestor, required string descendant ){
		return git( [ "merge-base", "--is-ancestor", arguments.ancestor, arguments.descendant ] ).exitCode == 0;
	}

	/** Returns the local branches whose names start with a prefix. */
	private array function branchesWithPrefix( required string prefix ){
		var names = [];
		var refs  = git( [ "for-each-ref", "--format=%(refname:short)", "refs/heads/" ] );
		for ( var name in listToArray( refs.output, chr( 10 ) ) ) {
			if ( startsWith( trim( name ), arguments.prefix ) ) {
				names.append( trim( name ) );
			}
		}
		return names;
	}

	private boolean function startsWith( required string text, required string prefix ){
		return len( arguments.prefix ) && left( arguments.text, len( arguments.prefix ) ) == arguments.prefix;
	}
}
