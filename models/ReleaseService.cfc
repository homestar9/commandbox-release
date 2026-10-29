/**
 * Checks, builds, and publishes one project version.
 *
 * `box release publish` checks Git, updates the publish branch, and builds the package.
 * It runs the beforePublish command from release.json when one is set. It publishes to
 * ForgeBox when enabled. Then it creates a Git tag and a GitHub Release when enabled.
 *
 * `box release publish <level>` changes the version and dates the [Unreleased] notes first.
 * It commits the change as "Release x.y.z" and then publishes.
 *
 * The publish branch is the branch that one run commits, tags, and pushes on. It is the
 * production branch from release.json. A branch listed in prereleaseBranches is the publish
 * branch for a prerelease version only. See ProjectConfig.publishBranchFor().
 *
 * All checks run before the command publishes or pushes anything. If a later step fails, the
 * command prints the steps for finishing the same release. Use `--dryRun` to build and check
 * without publishing, creating a tag, or pushing.
 *
 * If Gitflow or GitKraken made the version tag at this commit, the command uses that tag.
 * It pushes a local tag before creating the GitHub Release if the remote does not have the tag.
 */
component extends="commandbox-release.models.BaseService" {

	property name="changelogService" inject="ChangelogService@commandbox-release";
	property name="versionService"   inject="VersionService@commandbox-release";

	/**
	 * Publishes the version in box.json.
	 *
	 * @dryRun    Builds and checks the package. Shows publish, tag, and push steps without running them.
	 * @skipTests Skips the tests. Use only when the current version was already tested.
	 * @buildID   An optional build ID for the package. CI uses its run number.
	 * @sync      Gets new commits from the remote before building. The <level> flow already did this.
	 * @version   The version to publish. A practice run of publish <level> uses this because
	 *            box.json still has the old version.
	 * @testedOn  The branch where these files already passed the tests. The build does not run
	 *            them again.
	 * @skipHooks Skips the beforePublish command in release.json.
	 * @publishBranch The branch to sync and push. The default comes from the version and the
	 *            current branch. The Gitflow command passes production, because it publishes
	 *            there after the merges.
	 */
	function run(
		boolean dryRun       = false,
		boolean skipTests    = false,
		string buildID       = "",
		boolean sync         = true,
		string version       = "",
		string testedOn      = "",
		boolean skipHooks    = false,
		string publishBranch = ""
	){
		var releaseVersion = len( trim( arguments.version ) ) ? trim( arguments.version ) : variables.config.version();
		var tagName        = variables.settings.tagPrefix & releaseVersion;
		variables.publishedToForgeBox = false;
		variables.pushedToRemote      = false;
		variables.beforePublishRan    = false;
		usePublishBranch( releaseVersion, arguments.publishBranch );

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "PRACTICE RUN: Nothing will be published, tagged, or pushed." )
				.line()
				.toConsole();
		}

		// 1. Run every check before publishing or pushing anything.
		var tagMode = preflight( dryRun = arguments.dryRun, version = releaseVersion, skipHooks = arguments.skipHooks );
		var existingTag = tagMode == "existing";

		// 2. Update a branch-based release from the remote. A practice run does not update the
		//    branch. A tag-based release must build the exact commit that is already checked out.
		if ( existingTag ) {
			print.greenLine( "Using existing tag #tagName# at the current commit. Skipping the branch update." ).toConsole();
		} else if ( variables.settings.gitSync && arguments.sync && !arguments.dryRun ) {
			// The checks above used the commit before the pull. New commits from the remote could
			// change the version or the changelog, so stop and let the next run check them.
			var checkedCommit = repository().headCommit();
			syncWithRemote();
			if ( repository().headCommit() != checkedCommit ) {
				return stop(
					"The #variables.settings.remote# remote had new commits, and they are now in this checkout. Nothing was published. "
					& "Run the command again to check the updated project."
				);
			}
		} else if ( variables.settings.gitSync && arguments.dryRun ) {
			print.yellowLine( "Practice run: git pull was not run." ).toConsole();
		}

		// 3. Build the package. Failed tests stop the release.
		runBuild( releaseVersion, arguments.skipTests, arguments.buildID, arguments.testedOn );

		// 4. Run the beforePublish command from release.json. It runs before anything is published
		//    or pushed, so a push that starts a deploy comes after it. A failure stops the release.
		variables.beforePublishRan = service( "HookRunner" ).run(
			name   = "beforePublish",
			dryRun = arguments.dryRun,
			skip   = arguments.skipHooks
		);

		// 5. Publish to ForgeBox from the checked build folder.
		if ( variables.settings.publish.forgebox ) {
			publishToForgebox( releaseVersion, arguments.dryRun );
		} else {
			print.line().yellowLine( "ForgeBox publishing is off in release.json (publish.forgebox is false)." ).toConsole();
		}

		// 6. Create the tag and GitHub Release.
		if ( variables.settings.publish.github ) {
			github(
				version     = releaseVersion,
				dryRun      = arguments.dryRun,
				existingTag = existingTag
			);
		} else {
			print.yellowLine( "GitHub publishing is off in release.json (publish.github is false)." ).toConsole();
		}

		print.line().toConsole();
		if ( arguments.dryRun ) {
			print
				.boldGreenLine( "Practice run complete. Nothing was published." )
				.line( "The package was built and checked. Run box release publish to publish it." )
				.toConsole();
		} else {
			print.boldGreenLine( "Released #tagName#." ).toConsole();
		}
	}

	/**
	 * Changes the version, commits it, and publishes it. This is `box release publish <level>`.
	 *
	 * @level     The version change: major, minor, patch, prerelease, premajor, preminor,
	 *            prepatch, or none.
	 * @preid     A prerelease label. For example, minor with beta starts 1.1.0-beta.1.
	 * @dryRun    Shows version, commit, publish, tag, and push steps without running them.
	 * @skipTests Skips the tests.
	 * @buildID   An optional build ID for the package.
	 * @skipHooks Skips the beforePublish command in release.json.
	 * @finishPrerelease Allows the level to finish a prerelease without asking.
	 * @confirm   A function that asks a yes or no question. Without it, a level that finishes
	 *            a prerelease stops unless finishPrerelease is true.
	 */
	function release(
		required string level,
		string preid             = "",
		boolean dryRun           = false,
		boolean skipTests        = false,
		string buildID           = "",
		boolean skipHooks        = false,
		boolean finishPrerelease = false,
		any confirm              = ""
	){
		var bumper         = service( "VersionBumper" );
		var requestedLevel = bumper.ensureLevel( arguments.level );
		if ( len( trim( arguments.preid ) ) && listFindNoCase( "major,minor,patch", requestedLevel ) ) {
			requestedLevel = "pre" & requestedLevel;
		}

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "PRACTICE RUN: Nothing will be changed, committed, published, tagged, or pushed." )
				.line()
				.toConsole();
		}

		// 1. Check for problems before changing project files. The branch check needs the target
		//    version, because a prerelease branch publishes only prerelease versions.
		print.boldBlueLine( "=== Checking before the version change ===" ).toConsole();
		checkWorkingTree( checkRepository(), arguments.dryRun );
		checkGitflowBranch( requestedLevel );
		var target = targetVersion( requestedLevel, arguments.preid );
		usePublishBranch( target );
		checkBranchForBump( target, requestedLevel, arguments.dryRun );
		checkFinishedWithoutVersion( requestedLevel, arguments.preid );
		checkTagUnused( variables.settings.tagPrefix & target );
		print.greenLine( "  ok  #target# has not been released" ).toConsole();
		checkGitHubCli( arguments.dryRun );
		checkForgeBoxLogin( arguments.dryRun );
		checkUnreleasedNotes( target );
		print.greenLine( "  ok  [Unreleased] has release notes" ).toConsole();
		reviewVersionChange(
			current          = variables.config.version(),
			target           = target,
			advice           = "box release publish prerelease",
			dryRun           = arguments.dryRun,
			finishPrerelease = arguments.finishPrerelease,
			confirm          = arguments.confirm
		);

		// 2. Get new commits before making the release commit. Pulling later could fail because
		//    the new release commit would be in the way. The new commits must not change the
		//    version that was checked above.
		if ( variables.settings.gitSync && !arguments.dryRun ) {
			syncWithRemote();
			if ( targetVersion( requestedLevel, arguments.preid ) != target ) {
				return stop(
					"The #variables.settings.remote# remote had new commits that change the version in box.json, and they are now in this checkout. "
					& "Nothing was published. Run the command again to check the updated project."
				);
			}
		} else if ( variables.settings.gitSync ) {
			print.yellowLine( "Practice run: git pull was not run." ).toConsole();
		}

		// 3. Change the version and the changelog.
		print.line().boldBlueLine( "=== Changing the version ===" ).toConsole();
		var newVersion = bumper.run(
			level  = requestedLevel,
			preid  = arguments.preid,
			dryRun = arguments.dryRun,
			quiet  = true
		);

		// 4. Commit the two changed files.
		commitVersion( newVersion, arguments.dryRun );

		// 5. Publish. In a practice run, the new changelog section is not on disk. Use the text
		//    that the real version change would write.
		if ( arguments.dryRun ) {
			previewVersion( newVersion );
		}
		try {
			run(
				dryRun    = arguments.dryRun,
				skipTests = arguments.skipTests,
				buildID   = arguments.buildID,
				sync      = false,
				version   = arguments.dryRun ? newVersion : "",
				skipHooks = arguments.skipHooks
			);
		} catch ( any exception ) {
			if ( arguments.dryRun || variables.publishedToForgeBox || variables.pushedToRemote || left( exception.type ?: "", 8 ) != "Release." ) {
				rethrow;
			}
			print.line().redLine( exception.message ).toConsole();
			return stop(
				"Version #newVersion# is committed locally and nothing was published. "
				& hookNote()
				& "Fix the problem, and then run: box release publish"
			);
		}
	}

	/**
	 * Returns a sentence for recovery messages when the beforePublish command ran in the last
	 * run(). Its changes are already in place even though nothing was published. Returns an
	 * empty string when it did not run.
	 */
	string function hookNote(){
		return ( variables.beforePublishRan ?: false ) ? "The beforePublish command already ran. " : "";
	}

	/**
	 * Checks the release before publishing or pushing. Returns "existing" if the version tag
	 * points to the current commit. Returns "new" if the command must create the tag.
	 *
	 * run() sets the publish branch first. A direct call compares with the production branch.
	 *
	 * @dryRun    Allows conditions that are safe only during a practice run.
	 * @version   The version to check. The default is the box.json version.
	 * @skipHooks True when the release skips the beforePublish command.
	 */
	string function preflight( boolean dryRun = false, string version = "", boolean skipHooks = false ){
		var releaseVersion = len( trim( arguments.version ) ) ? trim( arguments.version ) : variables.config.version();
		var tagName        = variables.settings.tagPrefix & releaseVersion;

		print.boldBlueLine( "=== Checking ===" ).toConsole();
		checkWorkingTree( checkRepository(), arguments.dryRun );
		checkStableOnPrereleaseBranch( releaseVersion, arguments.dryRun );
		checkFinishedWithoutVersion();

		var tag         = detectTag( tagName );
		var existingTag = tag.mode == "existing";
		var branchName  = checkReleaseBranch( existingTag, arguments.dryRun );

		checkReleaseChangelog( releaseVersion );
		noteMissingIgnores();
		checkGitHubCli( arguments.dryRun );
		checkForgeBoxLogin( arguments.dryRun );

		printPreflightSummary(
			branchName,
			releaseVersion,
			tagName,
			arguments.dryRun,
			existingTag,
			tag.remote
		);
		if ( existingTag && branchName == publishBranch() ) {
			checkBranchForExistingTag( !arguments.skipHooks && len( service( "HookRunner" ).commandFor( "beforePublish" ) ) );
		}
		return tag.mode;
	}

	/**
	 * Runs the checks for `box release gitflow` before it changes branches or files.
	 *
	 * @version      The version to publish.
	 * @dryRun       Allows uncommitted files and skips service sign-in checks for a dry run.
	 * @requireNotes Checks for [Unreleased] notes when the command will prepare a new release
	 *               section. If false, check for a section for this version when GitHub is enabled.
	 * @replacesTag  A local tag on the current commit that the command will delete before the
	 *               release, such as the tag from a Gitflow finish. The remote must not have it.
	 */
	function checkGitflowRelease(
		required string version,
		boolean dryRun       = false,
		boolean requireNotes = true,
		string replacesTag   = ""
	){
		checkWorkingTree( checkRepository(), arguments.dryRun );
		checkTagUnused( variables.settings.tagPrefix & arguments.version, arguments.replacesTag );
		checkGitHubCli( arguments.dryRun );
		checkForgeBoxLogin( arguments.dryRun );
		if ( arguments.requireNotes ) {
			checkUnreleasedNotes( arguments.version );
			print.greenLine( "  ok  [Unreleased] has release notes" ).toConsole();
		} else {
			checkReleaseChangelog( arguments.version );
		}
		print.greenLine( "  ok  #arguments.version# has not been released" ).toConsole();
	}

	/**
	 * Saves a copy of the planned changelog in memory for release notes. A dry run uses this
	 * copy because it leaves the project's changelog file unchanged.
	 *
	 * @version The new version.
	 */
	function previewVersion( required string version ){
		var changelogPath = variables.config.repoPath( variables.settings.changelog );
		variables.changelogPreview = variables.changelogService.moveUnreleasedNotes(
			content       = fileRead( changelogPath ),
			version       = arguments.version,
			date          = dateFormat( now(), "yyyy-mm-dd" ),
			changelogName = variables.settings.changelog
		);
		return this;
	}

	/**
	 * Returns true if the last run() published to ForgeBox or pushed to the remote. The caller uses
	 * this result to avoid retrying the full release after either step has already happened.
	 */
	boolean function hasPublished(){
		return ( variables.publishedToForgeBox ?: false ) || ( variables.pushedToRemote ?: false );
	}

	/**
	 * Prints release notes for one version without publishing.
	 *
	 * @version The version to show. The default is the box.json version.
	 */
	function notes( string version = "" ){
		return github( version = arguments.version, notesOnly = true );
	}

	/**
	 * Finishes a release that stopped after publishing. It creates the tag when it is missing,
	 * pushes it, and creates the GitHub Release from the zip under .artifacts.
	 *
	 * @dryRun Prints the commands without running them.
	 */
	function resume( boolean dryRun = false ){
		var releaseVersion = variables.config.version();
		var tagName        = variables.settings.tagPrefix & releaseVersion;
		usePublishBranch( releaseVersion );
		var tag = detectTag( tagName );
		if ( tag.mode == "existing" ) {
			print.greenLine( "Tag #tagName# already points to the current commit." ).toConsole();
		}
		return github( version = releaseVersion, dryRun = arguments.dryRun, existingTag = tag.mode == "existing" );
	}

	// PUBLISH BRANCH

	/**
	 * Chooses the branch that this run commits, tags, and pushes on. A given branch wins.
	 * Otherwise the branch comes from the version and the current branch, read on first use so
	 * the repository checks run before the first Git call.
	 *
	 * @version The version to publish.
	 * @branch  A branch that the caller chose, or an empty string.
	 */
	private void function usePublishBranch( required string version, string branch = "" ){
		variables.publishVersion     = arguments.version;
		variables.publishBranchGiven = len( trim( arguments.branch ) ) > 0;
		if ( variables.publishBranchGiven ) {
			variables.publishBranchName = trim( arguments.branch );
		} else {
			structDelete( variables, "publishBranchName" );
		}
	}

	/** Returns the publish branch for this run. Before any run, it is the production branch. */
	private string function publishBranch(){
		if ( !structKeyExists( variables, "publishBranchName" ) ) {
			if ( !structKeyExists( variables, "publishVersion" ) ) {
				return variables.settings.branch;
			}
			variables.publishBranchName = variables.config.publishBranchFor( variables.publishVersion, repository().currentBranch() );
		}
		return variables.publishBranchName;
	}

	/** Returns "production branch master" or "prerelease branch develop" for messages. */
	private string function branchLabel( required string name ){
		return ( arguments.name == variables.settings.branch ? "production branch " : "prerelease branch " ) & arguments.name;
	}

	// PREFLIGHT CHECKS

	/** Checks for a Git repository and the release remote. Returns the uncommitted changes. */
	private array function checkRepository(){
		var changes = repository().changedFiles();
		if ( !len( repository().remoteUrl() ) ) {
			return stop(
				"Git has no remote named #variables.settings.remote#. Add it with: git remote add #variables.settings.remote# <url>. "
				& "Or set ""remote"" in release.json to the name of your GitHub remote."
			);
		}
		return changes;
	}

	private void function checkWorkingTree( required array changes, required boolean dryRun ){
		if ( variables.settings.requireCleanTree && arrayLen( arguments.changes ) ) {
			if ( arguments.dryRun ) {
				print
					.yellowLine( "  note  There are uncommitted changes. A real release would stop." )
					.toConsole();
			} else {
				return fail(
					"You have uncommitted changes. Commit or stash them, and then run this command again.",
					arguments.changes,
					"Uncommitted"
				);
			}
		}
	}

	/**
	 * Stops `publish` before the tag check when a prerelease branch holds a stable version. The
	 * tag check would otherwise report the stable tag on production first. A practice run warns.
	 * A run with a given publish branch, such as the Gitflow practice run, skips this check.
	 */
	private void function checkStableOnPrereleaseBranch( required string version, required boolean dryRun ){
		var branchName = repository().currentBranch();
		if ( variables.publishBranchGiven ?: false ) {
			return;
		}
		if ( !variables.config.isPrereleaseBranch( branchName ) || variables.versionService.isPrerelease( arguments.version ) ) {
			return;
		}
		if ( arguments.dryRun ) {
			warnStableOnPrereleaseBranch( branchName );
			return;
		}
		return fail(
			"#branchName# can publish only prerelease versions, and #arguments.version# is stable. Stable versions publish from production branch #variables.settings.branch#.",
			[
				"box release publish preminor alpha   (start a prerelease here)",
				"box release gitflow minor            (release a stable version)"
			]
		);
	}

	private void function warnStableOnPrereleaseBranch( required string branchName ){
		print
			.boldYellowLine( "  warning  This practice run is on #arguments.branchName#. A real run stops: #arguments.branchName# can publish only prerelease versions." )
			.toConsole();
	}

	private string function checkReleaseBranch( required boolean existingTag, required boolean dryRun ){
		var branchName = repository().currentBranch();
		var branch     = publishBranch();
		if ( arguments.existingTag && branchName != branch && branchName != "HEAD" ) {
			return stop(
				"A release of an existing tag must run from #branchLabel( branch )# or a detached tag checkout. "
				& "The current branch is #branchName#."
			);
		} else if ( !arguments.existingTag && branchName != branch && arguments.dryRun ) {
			// checkStableOnPrereleaseBranch() already warned on a prerelease branch.
			if ( ( variables.publishBranchGiven ?: false ) || !variables.config.isPrereleaseBranch( branchName ) ) {
				print
					.boldYellowLine( "  warning  This practice run is on #branchName#, not #branchLabel( branch )#." )
					.yellowLine( "           Run the real release from #branch#." )
					.toConsole();
			}
		} else if ( !arguments.existingTag && branchName != branch ) {
			return stop(
				"Releases must run from #branchLabel( branch )#. The current branch is #branchName#. "
				& "Switch branches or change ""branch"" in release.json."
			);
		}
		return branchName;
	}

	/**
	 * Stops `publish <level>` on a Gitflow release or hotfix branch. Change the version on that
	 * branch. Finish the Gitflow release to create the tag, then publish from production.
	 */
	private void function checkGitflowBranch( required string level ){
		var branchName = repository().currentBranch();
		var gitflow    = repository().gitflowBranches();
		for ( var kind in [ "release", "hotfix" ] ) {
			var prefix = gitflow[ kind & "Prefix" ];
			if ( len( branchName ) >= len( prefix ) && left( branchName, len( prefix ) ) == prefix ) {
				return fail(
					"You are on a Gitflow #kind# branch (#branchName#). Merge that branch and publish from #variables.settings.branch# using one of the options below.",
					[
						"Change the version, merge, and publish in one command:",
						"  box release gitflow #arguments.level#",
						"",
						"Or use GitKraken or git flow:",
						"  1. box release bump #arguments.level#         (on this branch)",
						"  2. Commit box.json and the changelog. Use the finish #kind# action in GitKraken or git flow to merge and tag the version.",
						"  3. Switch to #variables.settings.branch#. Run box release publish."
					],
					"Gitflow steps"
				);
			}
		}
	}

	/**
	 * Stops `publish <level>` outside the publish branch. The command must commit the version on
	 * the branch it will tag. A prerelease branch may publish a prerelease target only.
	 *
	 * @target The version that the level makes.
	 * @level  The level the user gave.
	 * @dryRun Warns instead of stopping.
	 */
	private void function checkBranchForBump( required string target, required string level, required boolean dryRun ){
		var branchName = repository().currentBranch();
		var production = variables.settings.branch;
		if ( branchName == publishBranch() ) {
			print.greenLine( "  ok  on #branchLabel( branchName )#" ).toConsole();
			return;
		}

		if ( variables.config.isPrereleaseBranch( branchName ) ) {
			if ( arguments.dryRun ) {
				warnStableOnPrereleaseBranch( branchName );
				return;
			}
			var gitflowLevel = arguments.level == "none" ? "minor" : arguments.level;
			return fail(
				"#branchName# can publish only prerelease versions, and #arguments.target# is stable. Stable versions publish from production branch #production#.",
				[
					"box release gitflow #gitflowLevel#   (release #arguments.target# through production)",
					prereleaseAdvice( arguments.level, arguments.target ) & "   (publish a prerelease here)"
				]
			);
		}

		if ( arguments.dryRun ) {
			print
				.boldYellowLine( "  warning  This practice run is on #branchName#, not production branch #production#." )
				.yellowLine( "           Run the real release from #production#." )
				.toConsole();
			return;
		}
		var steps = [
			"Switch to #production# and run the command again, or",
			"change the version here with box release bump, commit it, merge it into #production#, and run: box release publish"
		];
		if ( variables.versionService.isPrerelease( arguments.target ) ) {
			steps.append( "To publish prereleases from #branchName#, add it to ""prereleaseBranches"" in release.json." );
		}
		return fail(
			"box release publish <level> must run from production branch #production#. The current branch is #branchName#.",
			steps
		);
	}

	/**
	 * Returns the publish command that makes a prerelease on the current branch. When the level
	 * would finish the current prerelease, the next prerelease of that line is the match.
	 * Otherwise a new prerelease starts for the level.
	 */
	private string function prereleaseAdvice( required string level, required string target ){
		var current = variables.config.version();
		if ( variables.versionService.isPrerelease( current ) && coreVersion( current ) == coreVersion( arguments.target ) ) {
			return "box release publish prerelease";
		}
		var startLevel = listFindNoCase( "major,minor,patch", arguments.level ) ? arguments.level : "minor";
		return "box release publish pre#startLevel# alpha";
	}

	/** Returns major.minor.patch without a prerelease label or build metadata. */
	private string function coreVersion( required string version ){
		var parts = variables.versionService.parseVersion( arguments.version );
		return "#parts.major#.#parts.minor#.#parts.patch#";
	}

	/**
	 * Decides whether the release creates the tag or uses one that already exists. Stops when the
	 * tag cannot be used. Returns RepositoryService.tagRelease() with mode "new" or "existing".
	 */
	private struct function detectTag( required string tagName ){
		var tag    = repository().tagRelease( arguments.tagName );
		var remote = variables.settings.remote;
		switch ( tag.reason ) {
			case "localElsewhere":
				return stop(
					"Local tag #arguments.tagName# points to a different commit, so that version was already released. "
					& "Do not move a published tag. Change the version first: #bumpAdvice( versionOfTag( arguments.tagName ) )#"
				);
			case "remoteUnknown":
				return stop( "The #remote# remote could not be checked for tag #arguments.tagName# (#tag.output#). Nothing was published." );
			case "remoteElsewhere":
				return stop(
					tag.local == "atHead"
						? "Tag #arguments.tagName# points to a different commit on #remote#. Do not move a published tag. Check the release history or use a new version."
						: "Tag #arguments.tagName# already exists on #remote#, so that version was already released. Change the version first: #bumpAdvice( versionOfTag( arguments.tagName ) )#"
				);
			case "remoteOnly":
				return stop(
					"The #remote# remote has tag #arguments.tagName# at this commit, but this checkout does not. "
					& "Run: git fetch --tags #remote#, and then run this command again."
				);
		}
		return tag;
	}

	/** Returns the version part of a version tag. */
	private string function versionOfTag( required string tagName ){
		return mid( arguments.tagName, len( variables.settings.tagPrefix ) + 1, len( arguments.tagName ) );
	}

	/**
	 * Checks the publish branch on the remote before an existing tag is published. A Git GUI
	 * can finish a release and create its tag without pushing the branch. The release pushes it,
	 * so stop now if that push would fail.
	 *
	 * @hasHook True when the release will run a beforePublish command. If the branch is already
	 *          on the remote, a deploy may have started before that command runs.
	 */
	private void function checkBranchForExistingTag( boolean hasHook = false ){
		var branch = publishBranch();
		var remote = variables.settings.remote;
		switch ( repository().remoteBranchState( branch ) ) {
			case "contains":
				print.greenLine( "  ok  #branch# is on #remote#" ).toConsole();
				if ( arguments.hasHook ) {
					print
						.yellowLine( "  note  #branch# is already on #remote#, so this release does not push it. A deploy that starts" )
						.yellowLine( "        on a push may have started before the beforePublish command runs." )
						.toConsole();
				}
				return;
			case "diverged":
				return stop(
					"#remote#/#branch# has commits that this checkout does not have. Nothing was published. "
					& "Get them with git pull, and then check the release again."
				);
			case "unknown":
				print.yellowLine( "  note  Could not check #branch# on #remote#. The release will try to push it." ).toConsole();
				return;
		}
		print.yellowLine( "  note  #branch# has commits that are not on #remote#. The release will push it." ).toConsole();
	}

	/**
	 * Returns the version that `publish <level>` makes. Stops with the version error when the
	 * level does not fit, such as prerelease on a stable version. The level none keeps the
	 * current version.
	 */
	private string function targetVersion( required string level, string preid = "" ){
		try {
			return variables.versionService.nextVersion( variables.config.version(), arguments.level, trim( arguments.preid ) );
		} catch ( any exception ) {
			return stop( exception.message );
		}
	}

	/**
	 * Stops with recovery steps when a Gitflow finish tagged a version without changing box.json.
	 * GitKraken and git flow can merge a release or hotfix branch and tag it v2.0.1 while box.json
	 * still has 2.0.0. If the remote does not have the tag, the user can delete it and publish the
	 * version with box release gitflow. A tag on the remote is published, so the tag checks report
	 * it instead.
	 *
	 * It throws Release.FinishedWithoutVersion. The publish and gitflow commands catch it and can
	 * offer to do the steps. See finishedWithoutVersion().
	 *
	 * @level The level the user gave, if any.
	 * @preid The prerelease label the user gave, if any.
	 */
	void function checkFinishedWithoutVersion( string level = "", string preid = "" ){
		var finished = finishedWithoutVersion( arguments.level, arguments.preid );
		if ( structIsEmpty( finished ) ) {
			return;
		}
		var steps = [
			"The Gitflow finish merged and tagged the branch without changing the version.",
			"The tag is only on this computer. Delete it, and publish #finished.version# from #finished.branch#:",
			"  git tag -d #finished.tagName#",
			"  git switch -c #finished.branch#",
			"  box release gitflow #len( finished.level ) ? trim( finished.level & " " & finished.preid ) : "<level>   (choose the level that changes #finished.current# to #finished.version#)"#",
			"box release gitflow changes the version, merges #finished.branch# into both branches, and publishes."
		];
		if ( variables.versionService.finishesPrerelease( finished.current, finished.version ) ) {
			steps.append( "#finished.current# is a prerelease, so this finishes it and publishes stable version #finished.version#." );
		}
		steps.append( "" );
		steps.append( finished.canFix ? "box release can do these steps for you. When it asks, answer y. In a script, add --fixTag to the command." : finished.reason );
		return fail(
			"Tag #finished.tagName# is on this commit, but box.json still has version #finished.current#. Nothing was changed.",
			steps,
			"Finish #finished.version#",
			"Release.FinishedWithoutVersion"
		);
	}

	/**
	 * Finds a Gitflow finish that tagged a version without changing box.json. It looks for a
	 * version tag on the current commit that is newer than box.json and missing on the remote.
	 * Returns an empty struct when there is none. Otherwise it returns:
	 * - tagName, current (the box.json version), and version (the tag's version).
	 * - level and preid: the version change from current to version. level is empty if none fits.
	 * - branch: hotfix/<version> for a patch or prerelease, or release/<version> for a minor or
	 *   major version. Gitflow settings in Git config can change the prefixes.
	 * - canFix: true when box release can do the steps itself. When false, reason says why.
	 *
	 * @level The level the user gave. It must make the tag's version.
	 * @preid The prerelease label the user gave.
	 */
	struct function finishedWithoutVersion( string level = "", string preid = "" ){
		var current = variables.config.version();
		var prefix  = variables.settings.tagPrefix;
		for ( var tagName in repository().tagsAtHead() ) {
			var tagVersion = mid( tagName, len( prefix ) + 1, len( tagName ) );
			if ( left( tagName, len( prefix ) ) == prefix && isNewerVersion( tagVersion, current ) && repository().remoteTag( tagName ).status == "missing" ) {
				return describeFinish( tagName, current, tagVersion, arguments.level, arguments.preid );
			}
		}
		return {};
	}

	/** Builds the result of finishedWithoutVersion() for one tag. */
	private struct function describeFinish(
		required string tagName,
		required string current,
		required string version,
		string level = "",
		string preid = ""
	){
		var repo     = repository();
		var gitflow  = repo.gitflowBranches();
		var change   = gitflowLevel( arguments.current, arguments.version );
		var kind     = listFindNoCase( "major,minor,premajor,preminor", change.level ) ? "release" : "hotfix";
		var finished = {
			"tagName" : arguments.tagName,
			"current" : arguments.current,
			"version" : arguments.version,
			"level"   : change.level,
			"preid"   : change.preid,
			"branch"  : gitflow[ kind & "Prefix" ] & arguments.version,
			"canFix"  : false,
			"reason"  : ""
		};

		var production = variables.settings.branch;
		var branchName = repo.currentBranch();
		var requested  = requestedVersion( arguments.current, arguments.level, arguments.preid );
		if ( branchName != production ) {
			finished.reason = "box release can do these steps only on production branch #production#. The current branch is #branchName#.";
		} else if ( !repo.branchExists( gitflow.develop ) ) {
			finished.reason = "box release can do these steps only when branch #gitflow.develop# exists, because the steps merge into it.";
		} else if ( !len( change.level ) ) {
			finished.reason = "No version level changes #arguments.current# to #arguments.version#, so box release cannot do these steps.";
		} else if ( len( requested ) && requested != arguments.version ) {
			finished.reason = "The level you gave makes #requested#, but the tag is #arguments.tagName#. Check which version you meant. Leave out the level to publish #arguments.version#.";
		} else if ( repo.branchExists( finished.branch ) && !repo.isAncestor( finished.branch, "HEAD" ) ) {
			finished.reason = "#finished.branch# already exists and has commits that are not on #production#. Merge or delete it first.";
		} else {
			finished.canFix = true;
		}
		return finished;
	}

	/**
	 * Returns the version that a level the user gave makes from current. Returns an empty
	 * string when no level was given, or "invalid" when the level does not work.
	 */
	private string function requestedVersion( required string current, string level = "", string preid = "" ){
		var requested = trim( arguments.level );
		if ( !len( requested ) ) {
			return "";
		}
		if ( len( trim( arguments.preid ) ) && listFindNoCase( "major,minor,patch", requested ) ) {
			requested = "pre" & requested;
		}
		try {
			return variables.versionService.nextVersion( arguments.current, lCase( requested ), trim( arguments.preid ) );
		} catch ( any ignoredException ) {
			return "invalid";
		}
	}

	/** Returns true when first is newer than second. Returns false if either version is invalid. */
	private boolean function isNewerVersion( required string first, required string second ){
		try {
			return variables.versionService.compareVersions( arguments.first, arguments.second ) > 0;
		} catch ( any ignoredException ) {
			return false;
		}
	}

	/**
	 * Returns { level, preid } for the version change from current to target. A prerelease
	 * target, such as 1.1.0-rc.1, can also start with premajor, preminor, or prepatch and its
	 * label. level is empty when no change makes target.
	 */
	private struct function gitflowLevel( required string current, required string target ){
		var label = "";
		try {
			label = listFirst( variables.versionService.parseVersion( arguments.target ).prerelease, "." );
		} catch ( any ignoredException ) {
			return { "level" : "", "preid" : "" };
		}
		var changes = [
			{ "level" : "patch", "preid" : "" },
			{ "level" : "minor", "preid" : "" },
			{ "level" : "major", "preid" : "" },
			{ "level" : "prerelease", "preid" : "" }
		];
		if ( len( label ) ) {
			for ( var level in [ "prerelease", "prepatch", "preminor", "premajor" ] ) {
				changes.append( { "level" : level, "preid" : label } );
			}
		}
		for ( var change in changes ) {
			try {
				if ( variables.versionService.nextVersion( arguments.current, change.level, change.preid ) == arguments.target ) {
					return change;
				}
			} catch ( any ignoredException ) {
				// Try the next change.
			}
		}
		return { "level" : "", "preid" : "" };
	}

	/**
	 * Stops if the version tag exists locally or on the remote, or if the remote cannot be checked.
	 * The Gitflow command expects a new tag because it merges the branches before tagging.
	 *
	 * @tagName     The version tag.
	 * @replacesTag Allows this local tag when it is on the current commit. The command deletes it.
	 */
	private void function checkTagUnused( required string tagName, string replacesTag = "" ){
		var tag = repository().tagRelease( arguments.tagName );
		var replaced = len( arguments.replacesTag ) && arguments.tagName == arguments.replacesTag && tag.local == "atHead";
		if ( tag.local != "missing" && !replaced ) {
			return stop( "Tag #arguments.tagName# already exists. This command needs a new version tag. Choose another version level." );
		}
		if ( tag.remote == "unknown" ) {
			return stop( "The #variables.settings.remote# remote could not be checked for tag #arguments.tagName# (#tag.output#). Nothing was changed." );
		}
		if ( tag.remote == "present" ) {
			return stop( "Tag #arguments.tagName# already exists on #variables.settings.remote#. This command needs a new version tag. Choose another version level." );
		}
	}

	private void function checkReleaseChangelog( required string releaseVersion ){
		if ( variables.settings.publish.github ) {
			extractChangelogSection( arguments.releaseVersion );
		}
	}

	/**
	 * Lists recommended patterns missing from the box.json ignore list. Missing patterns do
	 * not stop the release. A package may need files that these patterns would exclude.
	 */
	private void function noteMissingIgnores(){
		var missing = missingPackageIgnores();
		if ( !arrayLen( missing ) ) {
			return;
		}
		print.yellowLine( "  note  box.json ignore list is missing #arrayLen( missing )# recommended pattern#( arrayLen( missing ) == 1 ? "" : "s" )#: #arrayToList( missing, ", " )#" ).toConsole();
		print.yellowLine( "        To add the missing patterns, run: box release init --yes" ).toConsole();
	}

	/**
	 * Stops when the [Unreleased] section is missing or empty, before any file changes. When a
	 * prerelease line ends with a stable version, each prerelease already took its notes, so the
	 * message says where the notes for the stable version go.
	 *
	 * @target The version that the release makes.
	 */
	private void function checkUnreleasedNotes( required string target ){
		var changelogPath = variables.config.repoPath( variables.settings.changelog );
		if ( !fileExists( changelogPath ) ) {
			return stop( "The project root does not contain #variables.settings.changelog#. Create it with: box release init" );
		}
		try {
			variables.changelogService.moveUnreleasedNotes(
				content       = fileRead( changelogPath ),
				version       = "0.0.0",
				date          = dateFormat( now(), "yyyy-mm-dd" ),
				changelogName = variables.settings.changelog
			);
		} catch ( "Release.Changelog.EmptyUnreleased" exception ) {
			var current = variables.config.version();
			var finishesPrerelease = variables.versionService.finishesPrerelease( current, arguments.target );
			return stop(
				exception.message
				& (
					finishesPrerelease
						? " #current# is a prerelease, so its notes stay in their own sections. Write the notes for #arguments.target# under [Unreleased]."
						: ""
				)
			);
		} catch ( any exception ) {
			return stop( exception.message );
		}
	}

	private void function checkGitHubCli( required boolean dryRun ){
		if ( variables.settings.publish.github && !arguments.dryRun ) {
			var signIn = host().signInState();
			if ( signIn.state == "missing" ) {
				return fail(
					"Could not find the GitHub CLI (gh).",
					[
						"Install it from https://cli.github.com. Then run: gh auth login",
						"",
						"If you just installed it, open a new terminal. A terminal keeps the PATH",
						"value from when it started and cannot see later changes."
					]
				);
			}
			if ( signIn.state == "signedOut" ) {
				return fail(
					"The GitHub CLI is not signed in. Nothing was published.",
					[ "gh auth login", "", "GitHub CLI output: " & signIn.output ]
				);
			}
		}
	}

	/**
	 * Check the ForgeBox sign-in before building. If publishing is on but nobody is signed in,
	 * stop before the tests and build.
	 */
	private void function checkForgeBoxLogin( required boolean dryRun ){
		if ( !variables.settings.publish.forgebox || arguments.dryRun ) {
			return;
		}
		var forgeBoxUser = "";
		try {
			forgeBoxUser = trim( command( "forgebox whoami" ).run( returnOutput = true ) );
		} catch ( any ignoredException ) {
			forgeBoxUser = "";
		}
		if ( !len( forgeBoxUser ) || forgeBoxUser contains "not logged in" ) {
			return fail(
				"You are not signed in to ForgeBox. Nothing was published.",
				[ "box forgebox login" ]
			);
		}
	}

	private void function printPreflightSummary(
		required string branchName,
		required string releaseVersion,
		required string tagName,
		required boolean dryRun,
		required boolean existingTag,
		string remoteTagStatus = ""
	){
		if ( arguments.existingTag ) {
			print.greenLine( "  ok  existing tag #arguments.tagName# points to the current commit" ).toConsole();
			if ( arguments.remoteTagStatus == "missing" ) {
				print.yellowLine( "  note  tag #arguments.tagName# is local only and will be pushed to #variables.settings.remote#" ).toConsole();
			} else {
				print.greenLine( "  ok  tag #arguments.tagName# is on #variables.settings.remote#" ).toConsole();
			}
		} else {
			print
				.greenLine( "  ok  clean checkout#( arguments.branchName == publishBranch() ? " on " & arguments.branchName : "" )#" )
				.greenLine( "  ok  #arguments.releaseVersion# has not been released" )
				.toConsole();
		}
		print
			.greenLine( variables.settings.publish.github ? "  ok  changelog entry found" : "  --  changelog not needed" )
			.greenLine( variables.settings.publish.github && !arguments.dryRun ? "  ok  GitHub CLI ready" : "  --  GitHub CLI not needed" )
			.greenLine( variables.settings.publish.forgebox && !arguments.dryRun ? "  ok  ForgeBox signed in" : "  --  ForgeBox login not needed" )
			.toConsole();
	}

	/**
	 * Creates and pushes a release tag. It creates a GitHub Release with changelog notes and
	 * attaches the built zip file.
	 *
	 * @version     The release version.
	 * @notesOnly   Prints release notes without creating or pushing a tag.
	 * @dryRun      Prints the commands without running them.
	 * @existingTag Uses a tag that already exists. It pushes the tag when the remote does not have it.
	 *              On the publish branch, it also pushes the branch when the remote is behind.
	 */
	private function github(
		string version      = "",
		boolean notesOnly   = false,
		boolean dryRun      = false,
		boolean existingTag = false
	){
		var releaseVersion = len( trim( arguments.version ) ) ? trim( arguments.version ) : variables.config.version();
		var tagName        = variables.settings.tagPrefix & releaseVersion;
		if ( arguments.existingTag ) {
			requireExistingTagAtHead( tagName );
		}

		var releaseNotes = extractChangelogSection( releaseVersion );
		if ( arguments.notesOnly ) {
			print.line().boldLine( "Release notes for #tagName#:" ).line( releaseNotes ).toConsole();
			return;
		}

		var ghArgs = buildGitHubArguments( releaseVersion, tagName, releaseNotes );

		if ( arguments.dryRun ) {
			return printGitHubDryRun( tagName, ghArgs, releaseNotes, arguments.existingTag );
		}

		return publishGitHubRelease( tagName, ghArgs, arguments.existingTag, releaseVersion );
	}

	// GITHUB RELEASE STEPS

	private array function buildGitHubArguments(
		required string releaseVersion,
		required string tagName,
		required string notes
	){
		var projectSlug = variables.config.slug();
		var zipPath = variables.config.repoPath(
			"#variables.settings.artifactsDir#/#projectSlug#/#arguments.releaseVersion#/#projectSlug#-#arguments.releaseVersion#.zip"
		);
		if ( !fileExists( zipPath ) ) {
			return stop( "The built zip file is missing at #zipPath#. Build it first: box release package" );
		}

		// Give the notes to GitHub CLI as a file so their Markdown does not change.
		var notesFile = variables.config.repoPath( "#variables.settings.stagingDir#/release-notes.md" );
		if ( !directoryExists( getDirectoryFromPath( notesFile ) ) ) {
			directoryCreate( getDirectoryFromPath( notesFile ), true, true );
		}
		fileWrite( notesFile, arguments.notes );

		var assets  = [ zipPath ];
		var shaPath = zipPath & ".sha512";
		if ( fileExists( shaPath ) ) {
			assets.append( shaPath );
		}
		return host().releaseArgs(
			tagName    = arguments.tagName,
			notesFile  = notesFile,
			assets     = assets,
			prerelease = isPrerelease( arguments.releaseVersion )
		);
	}

	private void function printGitHubDryRun(
		required string tagName,
		required array ghArgs,
		required string notes,
		required boolean existingTag
	){
		var preview = print.line().boldYellowLine( "Practice run. These commands would run next:" );
		if ( !arguments.existingTag ) {
			preview
				.line( "  git tag #arguments.tagName#" )
				.line( "  git push #variables.settings.remote# #publishBranch()#" )
				.line( "  git push #variables.settings.remote# #arguments.tagName#" );
		} else {
			if ( branchNeedsPush() ) {
				preview.line( "  git push #variables.settings.remote# #publishBranch()#" );
			}
			var remoteTag = repository().remoteTag( arguments.tagName );
			if ( remoteTag.status == "missing" ) {
				preview.line( "  git push #variables.settings.remote# #arguments.tagName#" );
			} else if ( remoteTag.status == "unknown" ) {
				preview.yellowLine( "  (The #variables.settings.remote# remote could not be checked. A real release pushes #arguments.tagName# when it is missing.)" );
			}
		}
		preview
			.line( "  gh " & arrayToList( arguments.ghArgs, " " ) )
			.line()
			.boldLine( "Release notes for the practice run:" )
			.line( arguments.notes )
			.toConsole();
	}

	private void function publishGitHubRelease(
		required string tagName,
		required array ghArgs,
		required boolean existingTag,
		required string version
	){
		print.line().boldBlueLine( "=== Tagging and releasing on GitHub ===" ).toConsole();

		if ( !arguments.existingTag ) {
			repository().createTag( arguments.tagName );

			try {
				repository().push( [ publishBranch() ] );
			} catch ( "Release.Git" exception ) {
				return failWithManualSteps( "Branch #publishBranch()# could not be pushed (#exception.detail#).", arguments.tagName, arguments.ghArgs );
			}
			variables.pushedToRemote = true;

			try {
				repository().push( [ arguments.tagName ] );
			} catch ( "Release.Git" exception ) {
				return failWithManualSteps( "The tag could not be pushed (#exception.detail#).", arguments.tagName, arguments.ghArgs );
			}
		} else {
			pushBranchForExistingTag( arguments.tagName, arguments.ghArgs );
			pushExistingTagIfMissing( arguments.tagName, arguments.ghArgs, arguments.version );
		}

		try {
			host().createRelease( arguments.ghArgs );
		} catch ( "Release.GitHub" exception ) {
			return fail(
				"The GitHub Release could not be created (#exception.detail#). The tag was already pushed.",
				[ "gh " & arrayToList( arguments.ghArgs, " " ), "", "Or run: box release resume" ],
				"Run this command to finish"
			);
		}

		print
			.greenLine(
				arguments.existingTag
					? "Created the GitHub Release for tag #arguments.tagName#."
					: "Created tag #arguments.tagName# and the GitHub Release."
			)
			.toConsole();
	}

	/**
	 * Returns true when the checkout is on the publish branch and the remote copy of that
	 * branch does not have the current commit. A detached tag checkout has no branch to push.
	 */
	private boolean function branchNeedsPush(){
		if ( repository().currentBranch() != publishBranch() ) {
			return false;
		}
		return listFindNoCase( "behind,missing,unknown", repository().remoteBranchState( publishBranch() ) ) > 0;
	}

	/**
	 * Pushes the publish branch before an existing tag. A Git GUI can finish a release and
	 * create its tag without pushing the branch. The resume command does not run the checks, so
	 * check again for remote commits that a push would reject. The tag can still be released then.
	 */
	private function pushBranchForExistingTag( required string tagName, required array ghArgs ){
		var branch = publishBranch();
		var remote = variables.settings.remote;
		if ( repository().currentBranch() != branch ) {
			return;
		}
		var state = repository().remoteBranchState( branch );
		if ( state == "contains" ) {
			return;
		}
		if ( state == "diverged" ) {
			print
				.yellowLine( "  warning  #remote#/#branch# has commits that this checkout does not have, so #branch# was not pushed." )
				.yellowLine( "           Merge them into #branch#, and then push it: git push #remote# #branch#" )
				.toConsole();
			return;
		}

		try {
			repository().push( [ branch ] );
		} catch ( "Release.Git" exception ) {
			return failWithManualSteps( "Branch #branch# could not be pushed (#exception.detail#).", arguments.tagName, arguments.ghArgs );
		}
		variables.pushedToRemote = true;
		print.greenLine( "Pushed #branch# to #remote#." ).toConsole();
	}

	/**
	 * Pushes an existing tag when the remote does not have it. This step runs right before creating
	 * the GitHub Release. It checks the remote again because the resume command can run by itself to
	 * finish a release that stopped earlier.
	 *
	 * @version The version of the tag. A prerelease may live on a prerelease branch.
	 */
	private function pushExistingTagIfMissing( required string tagName, required array ghArgs, required string version ){
		var remoteTag = repository().remoteTag( arguments.tagName );
		if ( remoteTag.status == "unknown" ) {
			return failWithManualSteps(
				"The #variables.settings.remote# remote could not be checked for tag #arguments.tagName# (#remoteTag.output#).",
				arguments.tagName,
				arguments.ghArgs,
				false
			);
		}
		if ( remoteTag.status == "present" ) {
			if ( remoteTag.commit != repository().headCommit() ) {
				return stop( "Tag #arguments.tagName# points to a different commit on #variables.settings.remote#. The release will not publish the wrong source." );
			}
			return;
		}

		try {
			repository().push( [ arguments.tagName ] );
		} catch ( "Release.Git" exception ) {
			return failWithManualSteps( "The tag could not be pushed (#exception.detail#).", arguments.tagName, arguments.ghArgs, false );
		}
		variables.pushedToRemote = true;
		print.greenLine( "Pushed tag #arguments.tagName# to #variables.settings.remote#." ).toConsole();
		if ( repository().currentBranch() != publishBranch() ) {
			warnIfBranchNotOnRemote( arguments.version );
		}
	}

	/**
	 * Warns when no branch on the remote may include the pushed tag's commit. Pushing a tag
	 * sends its commit to the remote, but it does not update any branch. A detached tag checkout
	 * has no branch to push, so the release only warns. A stable version belongs on production.
	 * A prerelease may also be on a prerelease branch.
	 *
	 * @version The version of the pushed tag.
	 */
	private void function warnIfBranchNotOnRemote( required string version ){
		var remote     = variables.settings.remote;
		var candidates = [ variables.settings.branch ];
		if ( variables.versionService.isPrerelease( arguments.version ) ) {
			candidates.append( variables.settings.prereleaseBranches, true );
		}
		var unknown = false;
		for ( var branch in candidates ) {
			var state = repository().remoteBranchState( branch );
			if ( state == "contains" ) {
				return;
			}
			unknown = unknown || state == "unknown";
		}

		if ( arrayLen( candidates ) == 1 ) {
			var branch = candidates[ 1 ];
			if ( unknown ) {
				print.yellowLine( "  warning  Could not confirm that #branch# is on #remote#. Push it if needed." ).toConsole();
			} else {
				print.yellowLine( "  warning  #remote#/#branch# does not contain this commit. Push the branch: git push #remote# #branch#" ).toConsole();
			}
			return;
		}

		var names = [];
		for ( var name in candidates ) {
			names.append( remote & "/" & name );
		}
		var list = arrayToList( names, ", " );
		if ( unknown ) {
			print.yellowLine( "  warning  Could not confirm that this commit is on #list#. Push the branch that holds it if needed." ).toConsole();
		} else {
			print.yellowLine( "  warning  None of #list# contains this commit. Push the branch that holds it." ).toConsole();
		}
	}

	// OTHER RELEASE HELPERS

	/**
	 * Checks that an existing lightweight or annotated tag points to the current commit. This
	 * prevents a recovery command from publishing files built from another commit.
	 */
	private function requireExistingTagAtHead( required string tagName ){
		var localTag = repository().localTag( arguments.tagName );
		if ( localTag == "missing" ) {
			return stop( "Tag #arguments.tagName# was expected, but this checkout does not contain it." );
		}
		if ( localTag != "atHead" ) {
			return stop( "Tag #arguments.tagName# does not point to the current commit. The release will not publish the wrong source." );
		}
	}

	/**
	 * Builds the package and stops the release after a build failure.
	 *
	 * @version   The version to build.
	 * @skipTests Skips the tests.
	 * @buildID   An optional build ID for the package.
	 * @testedOn  The branch where these files already passed the tests.
	 */
	private function runBuild(
		required string version,
		boolean skipTests = false,
		string buildID    = "",
		string testedOn   = ""
	){
		print.line().boldBlueLine( "=== Building ===" ).toConsole();

		try {
			service( "PackageBuilder" ).run(
				version   = arguments.version,
				skipTests = arguments.skipTests,
				buildID   = arguments.buildID,
				testedOn  = arguments.testedOn
			);
		} catch ( any exception ) {
			print.redLine( exception.message ).toConsole();
			return stop( "The build failed. Nothing was published." );
		}
	}

	/**
	 * Updates the current publish branch with a fast-forward from the remote. This includes remote
	 * changes without creating a merge commit. The earlier checks confirmed the branch and made
	 * sure there are no uncommitted changes.
	 */
	private function syncWithRemote(){
		print.line().boldBlueLine( "=== Updating from #variables.settings.remote# ===" ).toConsole();

		try {
			repository().pullFastForward( publishBranch() );
		} catch ( "Release.Git" exception ) {
			var guidance = [ exception.detail ];
			var help     = host().remoteHelp( variables.settings.remote, exception.detail );
			if ( arrayLen( help ) ) {
				guidance.append( "" );
				guidance.append( help, true );
			}
			return fail( "git pull failed.", guidance, "Git output" );
		}
		print.greenLine( "Up to date with #variables.settings.remote#/#publishBranch()#." ).toConsole();
	}

	/**
	 * Commits the version change. Stage only box.json and the changelog so unrelated changes do
	 * not enter the release commit.
	 *
	 * @version The new version.
	 * @dryRun  Prints the commands without running them.
	 */
	function commitVersion( required string version, required boolean dryRun ){
		var files   = [ "box.json", variables.settings.changelog ];
		var message = "Release #arguments.version#";

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "Practice run. These commands would run next:" )
				.line( "  git add #arrayToList( files, " " )#" )
				.line( "  git commit -m ""#message#""" )
				.toConsole();
			return;
		}

		try {
			repository().commitFiles( files, message );
		} catch ( "Release.Git" exception ) {
			return stop( "The release commit failed (#exception.detail#). box.json and the changelog were changed but not committed." );
		}
		print.greenLine( "Committed ""#message#""." ).toConsole();
	}

	/**
	 * Publishes the checked build folder instead of the project root.
	 *
	 * The build folder contains the files checked by the package step. CommandBox applies the
	 * box.json ignore list again while publishing. The same list was used during the build, so
	 * it should leave out no more files.
	 *
	 * @version The version to publish.
	 * @dryRun  Prints the publish commands without running them.
	 */
	private function publishToForgebox( required string version, boolean dryRun = false ){
		var slug       = variables.config.slug();
		var publishDir = variables.config.repoPath( "#variables.settings.stagingDir#/#slug#" );

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "Practice run. These ForgeBox commands would run next:" )
				.line( "  cd #publishDir#" )
				.line( "  publish" )
				.toConsole();
			return;
		}

		if ( !directoryExists( publishDir ) ) {
			return stop( "The built package folder is missing at #publishDir#. Run the package build again." );
		}

		print.line().boldBlueLine( "=== Publishing to ForgeBox ===" ).toConsole();

		// Save the current folder so a failed publish does not leave CommandBox in the
		// temporary build folder.
		var originalDir = variables.shell.pwd();
		try {
			command( "publish" ).inWorkingDirectory( publishDir & "/" ).run();
		} catch ( any exception ) {
			return stop( "ForgeBox publishing failed (#exception.message#). Check your sign-in status: box forgebox whoami" );
		} finally {
			variables.shell.cd( originalDir );
		}

		variables.publishedToForgeBox = true;
		print.greenLine( "Published #slug# #arguments.version# to ForgeBox." ).toConsole();
	}

	/**
	 * Stops after a late release failure and prints the commands needed to finish. The package
	 * may already be published, so running the full release again would fail its version checks.
	 *
	 * @reason            A description of the failure.
	 * @tagName           The release tag.
	 * @ghArgs            Arguments for the gh release command.
	 * @includeBranchPush Includes the branch push step. Leave it out after the branch was pushed.
	 */
	private function failWithManualSteps(
		required string reason,
		required string tagName,
		required array ghArgs,
		boolean includeBranchPush = true
	){
		var steps = [];
		if ( arguments.includeBranchPush ) {
			steps.append( "git push " & variables.settings.remote & " " & publishBranch() );
		}
		steps.append( "git push " & variables.settings.remote & " " & arguments.tagName );
		steps.append( "gh " & arrayToList( arguments.ghArgs, " " ) );
		steps.append( "" );
		steps.append( "Or fix the problem and run: box release resume" );

		return fail(
			arguments.reason & " The package may already be published. Run the listed commands instead of starting the full release again.",
			steps,
			"Run these commands to finish"
		);
	}

	/** Returns release notes for one version from the configured changelog. */
	private string function extractChangelogSection( required string version ){
		var changelogPath = variables.config.repoPath( variables.settings.changelog );
		var content       = "";
		if ( len( variables.changelogPreview ?: "" ) ) {
			content = variables.changelogPreview;
		} else if ( fileExists( changelogPath ) ) {
			content = fileRead( changelogPath );
		} else {
			return stop( "The project root does not contain #variables.settings.changelog#. Create it before releasing." );
		}

		try {
			return variables.changelogService.extractReleaseNotes(
				content       = content,
				version       = arguments.version,
				changelogName = variables.settings.changelog
			);
		} catch ( any exception ) {
			return stop( exception.message );
		}
	}

	/** Returns true for a prerelease version such as 1.0.0-beta.4. GitHub marks it as a prerelease. */
	private boolean function isPrerelease( required string version ){
		return variables.versionService.isPrerelease( arguments.version );
	}
}
