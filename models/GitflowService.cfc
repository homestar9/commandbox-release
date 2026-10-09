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
 */
component extends="commandbox-release.models.BaseService" {

	property name="versionService" inject="VersionService@commandbox-release";

	/**
	 * Creates a release branch when needed, merges it, and publishes the package.
	 *
	 * @level      The version change, such as patch or minor. Without a level, use box.json's
	 *             version if it is newer than production. Otherwise, use patch for a hotfix
	 *             or require a level. The none level keeps the version and dates the release notes.
	 * @preid      A prerelease label. For example, minor with beta starts 1.1.0-beta.1.
	 * @dryRun     Shows the steps and builds from the current branch. Writes build files but
	 *             leaves branches, box.json, and the changelog unchanged. Does not publish or push.
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

		if ( arguments.dryRun ) {
			return practice( flow, plan, release, arguments.preid, arguments.skipTests, arguments.keepBranch );
		}

		// 2. Get commits from the project's Git remote. If the current branch changes,
		//    stop so the next run can check the updated files.
		if ( variables.settings.gitSync ) {
			syncBranches( flow );
		}

		// 3. Create the release branch from develop.
		if ( flow.kind == "start" ) {
			var created = git( [ "switch", "-c", flow.branch, flow.develop ] );
			if ( created.exitCode != 0 ) {
				return stop( "#flow.branch# could not be created (#created.output#). Earlier branch updates from #variables.settings.remote# may still be in place." );
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
		publish( flow, release, plan.version, arguments.skipTests );

		// 8. Push both branches. Delete the release or hotfix branch unless keepBranch is true.
		finishBranches( flow, arguments.keepBranch );
	}

	// BRANCHES AND VERSION

	/**
	 * Reads the branch names and identifies the current branch. The returned kind is "start"
	 * on develop, "release" on a release branch, or "hotfix" on a hotfix branch.
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
					"On #flow.develop#:    box release gitflow minor   (creates a release branch, merges it, and publishes)",
					"On a release branch:  box release gitflow         (publishes the version in box.json if newer than production)",
					"On a hotfix branch:   box release gitflow         (publishes a patch unless box.json is already newer than production)"
				]
			);
		}

		for ( var name in [ flow.production, flow.develop ] ) {
			if ( !branchExists( name ) ) {
				return stop( "Branch #name# was not found on this computer. Create it or check it out from #variables.settings.remote# first." );
			}
		}
		return flow;
	}

	/**
	 * Chooses the release version. A level calculates a new version, except none keeps the
	 * current version. Without a level, use box.json's version if it is newer than production.
	 * Otherwise, use patch for a hotfix or ask the user for a level.
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
					"Choose a version level. Version #current# is not newer than the version on #arguments.flow.production#.",
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
	 * Reads production's box.json version from the last fetched copy of the remote branch first.
	 * The local production branch may contain a merge that an earlier run has not published yet.
	 * If the remote copy is missing, read the local branch. Return 0.0.0 if no version can be read.
	 */
	private string function releasedVersion( required string production ){
		for ( var ref in [ "refs/remotes/" & variables.settings.remote & "/" & arguments.production, "refs/heads/" & arguments.production ] ) {
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
		var openReleases = branchesWithPrefix( arguments.flow.releasePrefix );
		if ( arguments.flow.kind == "start" ) {
			if ( branchExists( arguments.flow.branch ) || remoteBranchExists( arguments.flow.branch ) ) {
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
		var fetched = git( [ "fetch", variables.settings.remote ] );
		if ( fetched.exitCode != 0 ) {
			return fail( "git fetch failed. Nothing was published or pushed.", [ fetched.output ], "Git output" );
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
		var remote = git( [ "rev-parse", "-q", "--verify", "refs/remotes/" & variables.settings.remote & "/" & arguments.name ] );
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
				"#arguments.name# and #variables.settings.remote#/#arguments.name# both have new commits. This branch was not updated. Earlier branch updates may still be in place.",
				[ "git switch #arguments.name#", "git pull #variables.settings.remote# #arguments.name#", "Resolve any conflicts and commit the merge. Switch back to #arguments.current#. Then run box release gitflow again." ],
				"Merge the local and remote commits first"
			);
		}

		var updated = arguments.name == arguments.current
			? git( [ "merge", "--ff-only", variables.settings.remote & "/" & arguments.name ] )
			: git( [ "update-ref", "refs/heads/" & arguments.name, remoteCommit, localCommit ] );
		if ( updated.exitCode != 0 ) {
			return stop( "#arguments.name# could not be updated from #variables.settings.remote# (#updated.output#)." );
		}
		print.line( "Updated #arguments.name# from #variables.settings.remote#." ).toConsole();
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
	 * if the target already contains that branch's commits. On a merge failure, try to cancel
	 * the merge and switch back to the release or hotfix branch.
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
					"Merge #arguments.flow.branch# into #arguments.target# and fix the conflicts:",
					"  git switch #arguments.target#",
					"  git merge --no-ff #arguments.flow.branch#",
					"Commit the resolved merge. Then return to the release or hotfix branch and publish:",
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
	 * Publishes from production. If tests passed on the release or hotfix branch and production
	 * has the same files, skip the second test run. Otherwise, run enabled tests during the build.
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

		var pushed = git( [ "push", variables.settings.remote, arguments.flow.production, arguments.flow.develop ] );
		if ( pushed.exitCode == 0 ) {
			print.greenLine( "Pushed #arguments.flow.production# and #arguments.flow.develop# to #variables.settings.remote#." ).toConsole();
		} else {
			print
				.yellowLine( "  warning  The branches could not be pushed (#pushed.output#)." )
				.yellowLine( "           Run: git push #variables.settings.remote# #arguments.flow.production# #arguments.flow.develop#" )
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
	 * Deletes the release or hotfix branch locally and on the remote. First, check that develop and
	 * production both contain all its commits. Then use git branch -D to delete the local branch.
	 * git branch -d can refuse to delete it when its tracked branch on the remote is behind.
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

		var onRemote = git( [ "ls-remote", "--exit-code", "--heads", variables.settings.remote, "refs/heads/" & branch ] );
		if ( onRemote.exitCode != 0 ) {
			return;
		}
		var remoteDeleted = git( [ "push", variables.settings.remote, "--delete", branch ] );
		if ( remoteDeleted.exitCode == 0 ) {
			print.greenLine( "Deleted #branch# on #variables.settings.remote#." ).toConsole();
		} else {
			print
				.yellowLine( "  warning  #branch# could not be deleted on #variables.settings.remote# (#remoteDeleted.output#)." )
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
		required boolean keepBranch
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

	/** Returns Git's ID for a branch's files. Matching IDs mean the files are identical. */
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
		return git( [ "rev-parse", "-q", "--verify", "refs/remotes/" & variables.settings.remote & "/" & arguments.branch ] ).exitCode == 0;
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
