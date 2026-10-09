/**
 * Checks, builds, and publishes one project version.
 *
 * `box release publish` checks Git, updates the production branch, and builds the package.
 * It publishes to ForgeBox when enabled. Then it creates a Git tag and a GitHub
 * Release when enabled.
 *
 * `box release publish <level>` changes the version and dates the [Unreleased] notes first.
 * It commits the change as "Release x.y.z" and then publishes.
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

	/**
	 * Publishes the version in box.json.
	 *
	 * @dryRun    Builds and checks the package. Shows publish, tag, and push steps without running them.
	 * @skipTests Skips the tests. Use only when the current version was already tested.
	 * @buildID   An optional build ID for the package. CI uses its run number.
	 * @sync      Gets new commits from the remote before building. The <level> flow already did this.
	 * @version   The version to publish. A practice run of publish <level> uses this because
	 *            box.json still has the old version.
	 */
	function run(
		boolean dryRun    = false,
		boolean skipTests = false,
		string buildID    = "",
		boolean sync      = true,
		string version    = ""
	){
		var releaseVersion = len( trim( arguments.version ) ) ? trim( arguments.version ) : variables.config.version();
		var tagName        = variables.settings.tagPrefix & releaseVersion;
		variables.publishedToForgeBox = false;
		variables.pushedToRemote      = false;

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "PRACTICE RUN: Nothing will be published, tagged, or pushed." )
				.line()
				.toConsole();
		}

		// 1. Run every check before publishing or pushing anything.
		var tagMode = preflight( dryRun = arguments.dryRun, version = releaseVersion );
		var existingTag = tagMode == "existing";

		// 2. Update a branch-based release from the remote. A practice run does not update the
		//    branch. A tag-based release must build the exact commit that is already checked out.
		if ( existingTag ) {
			print.greenLine( "Using existing tag #tagName# at the current commit. Skipping the branch update." ).toConsole();
		} else if ( variables.settings.gitSync && arguments.sync && !arguments.dryRun ) {
			// The checks above used the commit before the pull. New commits from the remote could
			// change the version or the changelog, so stop and let the next run check them.
			var checkedCommit = headCommit();
			syncWithRemote();
			if ( headCommit() != checkedCommit ) {
				return stop(
					"The #variables.settings.remote# remote had new commits, and they are now in this checkout. Nothing was published. "
					& "Run the command again to check the updated project."
				);
			}
		} else if ( variables.settings.gitSync && arguments.dryRun ) {
			print.yellowLine( "Practice run: git pull was not run." ).toConsole();
		}

		// 3. Build the package. Failed tests stop the release.
		runBuild( releaseVersion, arguments.skipTests, arguments.buildID );

		// 4. Publish to ForgeBox from the checked build folder.
		if ( variables.settings.publish.forgebox ) {
			publishToForgebox( releaseVersion, arguments.dryRun );
		} else {
			print.line().yellowLine( "ForgeBox publishing is off in release.json (publish.forgebox is false)." ).toConsole();
		}

		// 5. Create the tag and GitHub Release.
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
	 */
	function release(
		required string level,
		string preid      = "",
		boolean dryRun    = false,
		boolean skipTests = false,
		string buildID    = ""
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

		// 1. Check for problems before changing project files.
		print.boldBlueLine( "=== Checking before the version change ===" ).toConsole();
		var repositoryStatus = checkRepository();
		checkWorkingTree( repositoryStatus, arguments.dryRun );
		checkGitflowBranch( requestedLevel );
		checkProductionBranchForBump( arguments.dryRun );
		checkGitHubCli( arguments.dryRun );
		checkForgeBoxLogin( arguments.dryRun );
		checkUnreleasedNotes();
		print.greenLine( "  ok  [Unreleased] has release notes" ).toConsole();

		// 2. Get new commits before making the release commit. Pulling later could fail because
		//    the new release commit would be in the way.
		if ( variables.settings.gitSync && !arguments.dryRun ) {
			syncWithRemote();
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
				version   = arguments.dryRun ? newVersion : ""
			);
		} catch ( any exception ) {
			if ( arguments.dryRun || variables.publishedToForgeBox || variables.pushedToRemote || left( exception.type ?: "", 8 ) != "Release." ) {
				rethrow;
			}
			print.line().redLine( exception.message ).toConsole();
			return stop(
				"Version #newVersion# is committed locally and nothing was published. "
				& "Fix the problem, and then run: box release publish"
			);
		}
	}

	/**
	 * Checks the release before publishing or pushing. Returns "existing" if the version tag
	 * points to the current commit. Returns "new" if the command must create the tag.
	 *
	 * @dryRun  Allows conditions that are safe only during a practice run.
	 * @version The version to check. The default is the box.json version.
	 */
	string function preflight( boolean dryRun = false, string version = "" ){
		var releaseVersion = len( trim( arguments.version ) ) ? trim( arguments.version ) : variables.config.version();
		var tagName        = variables.settings.tagPrefix & releaseVersion;

		print.boldBlueLine( "=== Checking ===" ).toConsole();
		var repositoryStatus = checkRepository();
		checkWorkingTree( repositoryStatus, arguments.dryRun );

		var tag         = detectTag( tagName, arguments.dryRun );
		var existingTag = tag.mode == "existing";
		var branchName  = checkReleaseBranch( existingTag, arguments.dryRun );

		checkReleaseChangelog( releaseVersion );
		checkGitHubCli( arguments.dryRun );
		checkForgeBoxLogin( arguments.dryRun );

		printPreflightSummary(
			branchName,
			releaseVersion,
			tagName,
			arguments.dryRun,
			existingTag,
			tag.remote.status
		);
		return tag.mode;
	}

	/**
	 * Runs the checks for `box release gitflow` before it changes branches or files.
	 *
	 * @version      The version to publish.
	 * @dryRun       Allows uncommitted files and skips service sign-in checks for a dry run.
	 * @requireNotes Checks for [Unreleased] notes when the command will prepare a new release
	 *               section. If false, check for a section for this version when GitHub is enabled.
	 */
	function checkGitflowRelease( required string version, boolean dryRun = false, boolean requireNotes = true ){
		var repositoryStatus = checkRepository();
		checkWorkingTree( repositoryStatus, arguments.dryRun );
		checkTagUnused( variables.settings.tagPrefix & arguments.version );
		checkGitHubCli( arguments.dryRun );
		checkForgeBoxLogin( arguments.dryRun );
		if ( arguments.requireNotes ) {
			checkUnreleasedNotes();
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
		var tag            = detectTag( tagName, arguments.dryRun );
		if ( tag.mode == "existing" ) {
			print.greenLine( "Tag #tagName# already points to the current commit." ).toConsole();
		}
		return github( version = releaseVersion, dryRun = arguments.dryRun, existingTag = tag.mode == "existing" );
	}

	// PREFLIGHT CHECKS

	private struct function checkRepository(){
		var status = variables.config.execNative( "git", [ "status", "--porcelain" ] );
		if ( status.exitCode == 127 ) {
			return stop( "Git was not found. Install it, or open a new terminal if you installed it recently." );
		}
		if ( status.exitCode != 0 ) {
			return stop( "Git could not read this folder (#status.output#). Check that it is a Git repository." );
		}
		if ( !len( variables.config.remoteUrl() ) ) {
			return stop(
				"Git has no remote named #variables.settings.remote#. Add it with: git remote add #variables.settings.remote# <url>. "
				& "Or set ""remote"" in release.json to the name of your GitHub remote."
			);
		}
		return status;
	}

	private void function checkWorkingTree( required struct status, required boolean dryRun ){
		if ( variables.settings.requireCleanTree && len( trim( status.output ) ) ) {
			if ( arguments.dryRun ) {
				print
					.yellowLine( "  note  There are uncommitted changes. A real release would stop." )
					.toConsole();
			} else {
				return fail(
					"You have uncommitted changes. Commit or stash them, and then run this command again.",
					listToArray( status.output, chr( 10 ) ),
					"Uncommitted"
				);
			}
		}
	}

	/**
	 * Returns the current branch name, or HEAD for a detached checkout.
	 */
	private string function currentBranch(){
		var branch = variables.config.execNative( "git", [ "rev-parse", "--abbrev-ref", "HEAD" ] );
		if ( branch.exitCode != 0 ) {
			return stop( "Git could not identify the current branch (#branch.output#)." );
		}
		return trim( branch.output );
	}

	private string function checkReleaseBranch( required boolean existingTag, required boolean dryRun ){
		var branchName = currentBranch();
		if ( arguments.existingTag && branchName != variables.settings.branch && branchName != "HEAD" ) {
			return stop(
				"A release of an existing tag must run from production branch #variables.settings.branch# or a detached tag checkout. "
				& "The current branch is #branchName#."
			);
		} else if ( !arguments.existingTag && branchName != variables.settings.branch && arguments.dryRun ) {
			print
				.boldYellowLine( "  warning  This practice run is on #branchName#, not production branch #variables.settings.branch#." )
				.yellowLine( "           Run the real release from #variables.settings.branch#." )
				.toConsole();
		} else if ( !arguments.existingTag && branchName != variables.settings.branch ) {
			return stop(
				"Releases must run from production branch #variables.settings.branch#. The current branch is #branchName#. "
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
		var branchName = currentBranch();
		for ( var kind in [ "release", "hotfix" ] ) {
			var configured = variables.config.execNative( "git", [ "config", "--get", "gitflow.prefix." & kind ] );
			var prefix     = configured.exitCode == 0 && len( trim( configured.output ) ) ? trim( configured.output ) : kind & "/";
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
	 * Stops `publish <level>` outside the production branch. The command must commit the
	 * version on the branch it will tag.
	 */
	private void function checkProductionBranchForBump( required boolean dryRun ){
		var branchName = currentBranch();
		if ( branchName == variables.settings.branch ) {
			print.greenLine( "  ok  on production branch #branchName#" ).toConsole();
			return;
		}
		if ( arguments.dryRun ) {
			print
				.boldYellowLine( "  warning  This practice run is on #branchName#, not production branch #variables.settings.branch#." )
				.yellowLine( "           Run the real release from #variables.settings.branch#." )
				.toConsole();
			return;
		}
		return fail(
			"box release publish <level> must run from production branch #variables.settings.branch#. The current branch is #branchName#.",
			[
				"Switch to #variables.settings.branch# and run the command again, or",
				"change the version here with box release bump, commit it, merge it into #variables.settings.branch#, and run: box release publish"
			]
		);
	}

	/**
	 * Decides whether the release creates the tag or uses one that already exists.
	 *
	 * If the local tag points to this commit, use it. If it points elsewhere, stop because that
	 * version belongs to another commit. Check the remote the same way. Return "new" or "existing"
	 * and whether the remote has the tag.
	 */
	private struct function detectTag( required string tagName, required boolean dryRun ){
		var head        = headCommit();
		var localAtHead = false;

		var localTag = variables.config.execNative( "git", [ "rev-parse", "-q", "--verify", "refs/tags/" & arguments.tagName ] );
		if ( localTag.exitCode == 0 ) {
			var tagCommit = variables.config.execNative( "git", [ "rev-list", "-n", "1", "refs/tags/" & arguments.tagName ] );
			if ( tagCommit.exitCode == 0 && trim( tagCommit.output ) == head ) {
				localAtHead = true;
			} else {
				return stop(
					"Local tag #arguments.tagName# points to a different commit, so that version was already released. "
					& "Do not move a published tag. Change the version first: box release bump patch"
				);
			}
		}

		var remoteTag = remoteTagState( arguments.tagName );
		if ( remoteTag.status == "unknown" ) {
			return stop( "The #variables.settings.remote# remote could not be checked for tag #arguments.tagName# (#remoteTag.output#). Nothing was published." );
		}
		if ( remoteTag.status == "present" && remoteTag.commit != head ) {
			return stop(
				localAtHead
					? "Tag #arguments.tagName# points to a different commit on #variables.settings.remote#. Do not move a published tag. Check the release history or use a new version."
					: "Tag #arguments.tagName# already exists on #variables.settings.remote#, so that version was already released. Change the version first: box release bump patch"
			);
		}
		if ( remoteTag.status == "present" && !localAtHead ) {
			return stop(
				"The #variables.settings.remote# remote has tag #arguments.tagName# at this commit, but this checkout does not. "
				& "Run: git fetch --tags #variables.settings.remote#, and then run this command again."
			);
		}

		return {
			"mode"   : localAtHead ? "existing" : "new",
			"remote" : remoteTag
		};
	}

	/**
	 * Stops if the version tag exists locally or on the remote, or if the remote cannot be checked.
	 * The Gitflow command expects a new tag because it merges the branches before tagging.
	 */
	private void function checkTagUnused( required string tagName ){
		var localTag = variables.config.execNative( "git", [ "rev-parse", "-q", "--verify", "refs/tags/" & arguments.tagName ] );
		if ( localTag.exitCode == 0 ) {
			return stop( "Tag #arguments.tagName# already exists. This command needs a new version tag. Choose another version level." );
		}
		var remoteTag = remoteTagState( arguments.tagName );
		if ( remoteTag.status == "unknown" ) {
			return stop( "The #variables.settings.remote# remote could not be checked for tag #arguments.tagName# (#remoteTag.output#). Nothing was changed." );
		}
		if ( remoteTag.status == "present" ) {
			return stop( "Tag #arguments.tagName# already exists on #variables.settings.remote#. This command needs a new version tag. Choose another version level." );
		}
	}

	private void function checkReleaseChangelog( required string releaseVersion ){
		if ( variables.settings.publish.github ) {
			extractChangelogSection( arguments.releaseVersion );
		}
	}

	/**
	 * Stops when the [Unreleased] section is missing or empty, before any file changes.
	 */
	private void function checkUnreleasedNotes(){
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
		} catch ( any exception ) {
			return stop( exception.message );
		}
	}

	private void function checkGitHubCli( required boolean dryRun ){
		if ( variables.settings.publish.github && !arguments.dryRun ) {
			var ghCheck = variables.config.execNative( "gh", [ "auth", "status" ] );
			if ( ghCheck.exitCode == 127 ) {
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
			if ( ghCheck.exitCode != 0 ) {
				return fail(
					"The GitHub CLI is not signed in. Nothing was published.",
					[ "gh auth login", "", "GitHub CLI output: " & ghCheck.output ]
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
				.greenLine( "  ok  clean checkout#( arguments.branchName == variables.settings.branch ? " on " & variables.settings.branch : "" )#" )
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

		return publishGitHubRelease( tagName, ghArgs, arguments.existingTag );
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

		var ghArgs = [ "release", "create", arguments.tagName, "--title", arguments.tagName, "--notes-file", notesFile ];
		if ( isPrerelease( arguments.releaseVersion ) ) {
			ghArgs.append( "--prerelease" );
		}
		// gh picks its own repository when the checkout has more than one remote. Use the repository
		// that the tag is pushed to.
		var gitHubRepo = variables.config.gitHubRepo();
		if ( len( gitHubRepo ) ) {
			ghArgs.append( [ "--repo", gitHubRepo ], true );
		}
		ghArgs.append( zipPath );

		var shaPath = zipPath & ".sha512";
		if ( fileExists( shaPath ) ) {
			ghArgs.append( shaPath );
		}
		return ghArgs;
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
				.line( "  git push #variables.settings.remote# #variables.settings.branch#" )
				.line( "  git push #variables.settings.remote# #arguments.tagName#" );
		} else {
			var remoteTag = remoteTagState( arguments.tagName );
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
		required boolean existingTag
	){
		print.line().boldBlueLine( "=== Tagging and releasing on GitHub ===" ).toConsole();

		var result = { exitCode : 0, output : "" };
		if ( !arguments.existingTag ) {
			result = variables.config.execNative( "git", [ "tag", arguments.tagName ] );
			if ( result.exitCode != 0 ) {
				return stop( "Tag #arguments.tagName# could not be created: #result.output#" );
			}

			result = variables.config.execNative( "git", [ "push", variables.settings.remote, variables.settings.branch ] );
			if ( result.exitCode != 0 ) {
				return failWithManualSteps( "The production branch could not be pushed (#result.output#).", arguments.tagName, arguments.ghArgs );
			}
			variables.pushedToRemote = true;

			result = variables.config.execNative( "git", [ "push", variables.settings.remote, arguments.tagName ] );
			if ( result.exitCode != 0 ) {
				return failWithManualSteps( "The tag could not be pushed (#result.output#).", arguments.tagName, arguments.ghArgs );
			}
		} else {
			pushExistingTagIfMissing( arguments.tagName, arguments.ghArgs );
		}

		result = variables.config.execNative( "gh", arguments.ghArgs );
		if ( result.exitCode != 0 ) {
			return fail(
				"The GitHub Release could not be created (#result.output#). The tag was already pushed.",
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
	 * Pushes an existing tag when the remote does not have it. This step runs right before creating
	 * the GitHub Release. It checks the remote again because the resume command can run by itself to
	 * finish a release that stopped earlier.
	 */
	private function pushExistingTagIfMissing( required string tagName, required array ghArgs ){
		var remoteTag = remoteTagState( arguments.tagName );
		if ( remoteTag.status == "unknown" ) {
			return failWithManualSteps(
				"The #variables.settings.remote# remote could not be checked for tag #arguments.tagName# (#remoteTag.output#).",
				arguments.tagName,
				arguments.ghArgs,
				false
			);
		}
		if ( remoteTag.status == "present" ) {
			if ( remoteTag.commit != headCommit() ) {
				return stop( "Tag #arguments.tagName# points to a different commit on #variables.settings.remote#. The release will not publish the wrong source." );
			}
			return;
		}

		var result = variables.config.execNative( "git", [ "push", variables.settings.remote, arguments.tagName ] );
		if ( result.exitCode != 0 ) {
			return failWithManualSteps( "The tag could not be pushed (#result.output#).", arguments.tagName, arguments.ghArgs, false );
		}
		variables.pushedToRemote = true;
		print.greenLine( "Pushed tag #arguments.tagName# to #variables.settings.remote#." ).toConsole();
		warnIfBranchNotOnRemote();
	}

	/**
	 * Warns when the production branch may not include the pushed tag's commit. Pushing a tag
	 * sends its commit to the remote, but it does not update the production branch.
	 */
	private void function warnIfBranchNotOnRemote(){
		var branch  = variables.settings.branch;
		var remote  = variables.settings.remote;
		var unknown = "  warning  Could not confirm that #branch# is on #remote#. Push it if needed.";

		var remoteBranch = variables.config.execNative( "git", [ "ls-remote", remote, "refs/heads/" & branch ] );
		if ( remoteBranch.exitCode != 0 || !len( trim( remoteBranch.output ) ) ) {
			print.yellowLine( unknown ).toConsole();
			return;
		}

		var remoteCommit = listFirst( listFirst( remoteBranch.output, chr( 10 ) ), chr( 9 ) );
		var ancestry     = variables.config.execNative( "git", [ "merge-base", "--is-ancestor", "HEAD", remoteCommit ] );
		if ( ancestry.exitCode == 1 ) {
			print
				.yellowLine( "  warning  #remote#/#branch# does not contain this commit. Push the branch: git push #remote# #branch#" )
				.toConsole();
		} else if ( ancestry.exitCode != 0 ) {
			print.yellowLine( unknown ).toConsole();
		}
	}

	// OTHER RELEASE HELPERS

	/**
	 * Checks that an existing lightweight or annotated tag points to the current commit. This
	 * prevents a recovery command from publishing files built from another commit.
	 */
	private function requireExistingTagAtHead( required string tagName ){
		var tagCheck = variables.config.execNative( "git", [ "rev-parse", "-q", "--verify", "refs/tags/" & arguments.tagName ] );
		if ( tagCheck.exitCode != 0 ) {
			return stop( "Tag #arguments.tagName# was expected, but this checkout does not contain it." );
		}

		var tagCommit = variables.config.execNative( "git", [ "rev-list", "-n", "1", "refs/tags/" & arguments.tagName ] );
		if ( tagCommit.exitCode != 0 || trim( tagCommit.output ) != headCommit() ) {
			return stop( "Tag #arguments.tagName# does not point to the current commit. The release will not publish the wrong source." );
		}
	}

	/**
	 * Checks one tag on the remote without downloading it. The returned status is "present",
	 * "missing", or "unknown". A present tag also includes its commit.
	 *
	 * git ls-remote prints each match as "<sha><tab><ref>". An annotated tag adds a second line
	 * ending in ^{}. The SHA on that line is the tagged commit. A lightweight tag already uses
	 * the commit SHA. Exit code 2 means that the remote does not have the tag. Another nonzero code
	 * means that the remote could not be checked.
	 */
	private struct function remoteTagState( required string tagName ){
		var result = variables.config.execNative(
			"git",
			[ "ls-remote", "--exit-code", "--tags", variables.settings.remote, "refs/tags/" & arguments.tagName ]
		);
		if ( result.exitCode == 2 ) {
			return { status : "missing", commit : "", output : result.output };
		}
		if ( result.exitCode != 0 ) {
			return { status : "unknown", commit : "", output : result.output };
		}

		var commit = "";
		for ( var line in listToArray( result.output, chr( 10 ) ) ) {
			var sha = trim( listFirst( line, chr( 9 ) ) );
			var ref = trim( listLast( line, chr( 9 ) ) );
			if ( right( ref, 3 ) == "^{}" ) {
				commit = sha;
				break;
			}
			if ( ref == "refs/tags/" & arguments.tagName ) {
				commit = sha;
			}
		}
		return { status : "present", commit : commit, output : result.output };
	}

	/** Returns the full SHA for the current commit. */
	private string function headCommit(){
		var head = variables.config.execNative( "git", [ "rev-parse", "HEAD" ] );
		if ( head.exitCode != 0 ) {
			return stop( "Git could not identify the current commit (#head.output#)." );
		}
		return trim( head.output );
	}

	/**
	 * Builds the package and stops the release after a build failure.
	 *
	 * @version   The version to build.
	 * @skipTests Skips the tests.
	 * @buildID   An optional build ID for the package.
	 */
	private function runBuild( required string version, boolean skipTests = false, string buildID = "" ){
		print.line().boldBlueLine( "=== Building ===" ).toConsole();

		try {
			service( "PackageBuilder" ).run(
				version   = arguments.version,
				skipTests = arguments.skipTests,
				buildID   = arguments.buildID
			);
		} catch ( any exception ) {
			print.redLine( exception.message ).toConsole();
			return stop( "The build failed. Nothing was published." );
		}
	}

	/**
	 * Updates the current production branch with a fast-forward from the remote. This includes remote
	 * changes without creating a merge commit. The earlier checks confirmed the branch and made
	 * sure there are no uncommitted changes.
	 */
	private function syncWithRemote(){
		print.line().boldBlueLine( "=== Updating from #variables.settings.remote# ===" ).toConsole();

		var result = variables.config.execNative( "git", [ "pull", "--ff-only", variables.settings.remote, variables.settings.branch ] );
		if ( result.exitCode != 0 ) {
			var guidance = [ result.output ];
			if ( result.output contains "publickey" ) {
				guidance.append( "" );
				guidance.append( "Git cannot sign in to the remote. Add your SSH key at:" );
				guidance.append( "https://github.com/settings/ssh/new, or change the remote to HTTPS:" );
				guidance.append( "" );
				guidance.append( "  git remote set-url #variables.settings.remote# https://github.com/<you>/<repo>.git" );
				guidance.append( "  gh auth setup-git" );
			}
			return fail( "git pull failed.", guidance, "Git output" );
		}
		print.greenLine( "Up to date with #variables.settings.remote#/#variables.settings.branch#." ).toConsole();
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

		var added = variables.config.execNative( "git", [ "add" ].append( files, true ) );
		if ( added.exitCode != 0 ) {
			return stop( "The version files could not be staged (#added.output#). box.json and the changelog were changed but not committed." );
		}
		var committed = variables.config.execNative( "git", [ "commit", "-m", message ] );
		if ( committed.exitCode != 0 ) {
			return stop( "The release commit failed (#committed.output#). box.json and the changelog were changed but not committed." );
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
	 * @includeBranchPush Includes the branch push step. An existing tag does not push a branch.
	 */
	private function failWithManualSteps(
		required string reason,
		required string tagName,
		required array ghArgs,
		boolean includeBranchPush = true
	){
		var steps = [];
		if ( arguments.includeBranchPush ) {
			steps.append( "git push " & variables.settings.remote & " " & variables.settings.branch );
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

	/**
	 * Returns true when a version has a prerelease label after a hyphen, such as
	 * 1.0.0-beta.4. GitHub uses this result to mark a prerelease.
	 */
	private boolean function isPrerelease( required string version ){
		return find( "-", arguments.version ) > 0;
	}
}
