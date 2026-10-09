/**
 * Checks whether a project is ready for a release.
 *
 * `box release check` checks the module version, settings, Git, changelog, required tools,
 * and test server. It reports every problem it finds.
 *
 * It does not change files, Git data, servers, or remote services.
 */
component extends="commandbox-release.models.BaseService" {

	/**
	 * Runs all checks, prints a summary, and returns the number of problems.
	 *
	 * @root The project root folder.
	 */
	numeric function run( required string root ){
		print.line().boldLine( "Release readiness" ).line( repeatString( "-", 60 ) ).toConsole();

		variables.problems = 0;
		var configError    = loadProject( arguments.root );
		if ( len( configError ) ) {
			report( true, "module", "commandbox-release " & moduleVersion() );
			report( false, "release.json", configError, "Fix release.json, then run this again." );
			print.line().boldRedLine( "The remaining checks need valid project settings." ).toConsole();
			return stop( "The project settings could not be read." );
		}

		checkModule();
		checkConfig();
		checkGit();
		checkChangelog();
		checkTools();
		checkServer();

		print.line( repeatString( "-", 60 ) ).toConsole();
		if ( variables.problems == 0 ) {
			print
				.boldGreenLine( "The project is ready for a release." )
				.line( "To check and build the release without publishing, run: box release publish --dryRun" )
				.toConsole();
		} else {
			print
				.boldYellowLine( "Fix #variables.problems# problem#( variables.problems == 1 ? "" : "s" )# before releasing." )
				.toConsole();
		}
		return variables.problems;
	}

	/**
	 * Tries to load project settings without stopping the report. It returns the error message
	 * or an empty string when the settings load.
	 */
	private string function loadProject( required string root ){
		try {
			variables.config   = variables.wirebox.getInstance( "ProjectConfig@commandbox-release" ).load( arguments.root );
			variables.settings = variables.config.getSettings();
			variables.root     = variables.config.getRoot();
			return "";
		} catch ( any exception ) {
			return exception.message;
		}
	}

	// READINESS CHECKS

	/**
	 * Reports the installed module version and the settings file.
	 */
	private function checkModule(){
		print.line().boldLine( "commandbox-release" ).toConsole();
		report( true, "module", "commandbox-release " & moduleVersion() );

		if ( !len( variables.config.configPath() ) ) {
			report( false, "settings", "release.json is missing", "Create it with: box release init" );
		} else {
			report( true, "settings", "release.json" );
		}
	}

	/**
	 * Prints the settings that the release will use.
	 */
	private function checkConfig(){
		print.line().boldLine( "Settings" ).toConsole();
		var publishSummary = "ForgeBox=#yesNo( variables.settings.publish.forgebox )#  "
			& "GitHub=#yesNo( variables.settings.publish.github )#";
		print
			.line( "        project:   #variables.config.slug()# #variables.config.version()#" )
			.line( "        root:      #variables.root#" )
			.line( "        branch:    #variables.settings.branch#" )
			.line( "        remote:    #variables.settings.remote#" )
			.line( "        publish:   #publishSummary#" )
			.line( "        tests:     #( variables.settings.runTests ? "run during build" : "disabled in release.json" )#" )
			.toConsole();
	}

	/**
	 * Checks for Git and a Git repository before running the other Git checks.
	 */
	private function checkGit(){
		print.line().boldLine( "Git" ).toConsole();

		var changes = [];
		try {
			changes = repository().changedFiles();
		} catch ( "Release.Git.Missing" exception ) {
			report(
				false,
				"git",
				"not found",
				"Install Git. If you just installed it, open a new terminal so CommandBox can find it."
			);
			return;
		} catch ( "Release.Git" exception ) {
			report( false, "git", "not a repository", "Run this command inside the project's Git repository." );
			return;
		}
		report( true, "git", "found at " & variables.config.findBinary( "git" ) );
		checkWorkingTree( changes );
		gitCheck( "branch", function(){ checkReleaseBranch(); } );
		gitCheck( "version", function(){ checkVersionTag(); } );
		gitCheck( "remote", function(){ checkRemote(); } );
	}

	/**
	 * Runs one Git check. A Git failure becomes a reported problem, so the other checks still run.
	 */
	private void function gitCheck( required string label, required any check ){
		try {
			arguments.check();
		} catch ( "Release.Git" exception ) {
			report( false, arguments.label, exception.message );
		}
	}

	private void function checkWorkingTree( required array changes ){
		if ( arrayLen( arguments.changes ) ) {
			var changed = arrayLen( arguments.changes );
			report(
				false,
				"clean checkout",
				"#changed# uncommitted change#( changed == 1 ? "" : "s" )#",
				"Run git status. Stage the files with git add, and then commit them."
			);
		} else {
			report( true, "clean checkout", "no uncommitted changes" );
		}
	}

	private void function checkReleaseBranch(){
		var branch = repository().currentBranch();
		if ( branch != variables.settings.branch ) {
			report(
				false,
				"branch",
				"current branch is #branch#. Releases use production branch #variables.settings.branch#",
				"Switch with: git switch #variables.settings.branch#   (or correct ""branch"" in release.json)"
			);
		} else {
			report( true, "branch", branch );
		}
	}

	/**
	 * Checks whether the current version tag can be released. It uses the same rule as
	 * box release publish. See RepositoryService.tagRelease().
	 */
	private void function checkVersionTag(){
		var tagName = variables.settings.tagPrefix & variables.config.version();
		var remote  = variables.settings.remote;
		var tag     = repository().tagRelease( tagName );
		var bump    = "Change the version first: box release bump patch";

		switch ( tag.reason ) {
			case "localElsewhere":
				report( false, "version", "#tagName# is already released", bump );
				return;
			case "remoteElsewhere":
				report( false, "version", "#tagName# is already released (on #remote#)", bump );
				return;
			case "remoteOnly":
				report( false, "version", "#tagName# is on #remote# but not in this checkout", "Run: git fetch --tags #remote#" );
				return;
			case "remoteUnknown":
				report( false, "version", "the #remote# remote could not be checked for #tagName#", "See the remote check below." );
				return;
		}

		if ( tag.mode == "new" ) {
			report( true, "version", "#tagName# has not been released" );
		} else if ( tag.remote == "missing" ) {
			report( true, "version", "#tagName# points to this commit but is not on #remote#. box release publish will push it" );
		} else {
			report( true, "version", "#tagName# points to this commit. box release publish will use this tag" );
		}
	}

	private void function checkRemote(){
		var name = variables.settings.remote;
		if ( !len( repository().remoteUrl() ) ) {
			report(
				false,
				"remote",
				"no remote named #name#",
				"Add it with: git remote add #name# <url>. Or set ""remote"" in release.json to the name of your GitHub remote."
			);
			return;
		}
		var reached = repository().canReachRemote();
		if ( !reached.ok ) {
			var help = host().remoteHelp( name, reached.output );
			report(
				false,
				"remote",
				"cannot reach #name#",
				arrayLen( help ) ? help : "Check the remote address and your access: git remote -v"
			);
		} else {
			report( true, "remote", "#name# reachable" );
		}
	}

	/**
	 * Checks that the changelog exists and contains the required sections.
	 */
	private function checkChangelog(){
		print.line().boldLine( "Changelog" ).toConsole();

		var path = variables.config.repoPath( variables.settings.changelog );
		if ( !fileExists( path ) ) {
			report(
				false,
				variables.settings.changelog,
				"missing",
				"Create it: box release init"
			);
			return;
		}

		var body    = fileRead( path );
		var version = variables.config.version();

		// CFML uses ## for one literal # inside a string. The #### pattern matches a Markdown
		// level-two heading that starts with ##.
		if ( !reFindNoCase( "####\s*\[Unreleased\]", body ) ) {
			report(
				false,
				"[Unreleased]",
				"no [Unreleased] section",
				"Add a ""#### [Unreleased]"" heading. Write new notes below the heading."
			);
		} else {
			report( true, "[Unreleased]", "present" );
		}

		if ( body contains "[#version#]" ) {
			report( true, "notes for #version#", "found" );
		} else {
			report(
				false,
				"notes for #version#",
				"no ""#### [#version#]"" section",
				variables.settings.publish.github
					? "Run box release bump patch to date the notes, or run box release publish patch to date and publish them."
					: "This section is only needed for a GitHub Release. GitHub publishing is off in release.json."
			);
		}
	}

	/**
	 * Checks the publishing tools that are enabled in release.json.
	 */
	private function checkTools(){
		print.line().boldLine( "Tools" ).toConsole();
		checkGitHubCli();
		checkForgeBoxLogin();
	}

	private void function checkGitHubCli(){
		if ( variables.settings.publish.github ) {
			var signIn = host().signInState();
			if ( signIn.state == "missing" ) {
				report(
					false,
					"GitHub CLI",
					"not found",
					"Install it from https://cli.github.com. Then run: gh auth login. Open a new terminal if you just installed it."
				);
			} else if ( signIn.state == "signedOut" ) {
				report( false, "GitHub CLI", "not signed in", "Run: gh auth login" );
			} else {
				report( true, "GitHub CLI", "signed in" );
			}
		} else {
			report( true, "GitHub CLI", "not needed (publish.github is false)" );
		}
	}

	private void function checkForgeBoxLogin(){
		if ( variables.settings.publish.forgebox ) {
			var forgeBoxUser = "";
			try {
				forgeBoxUser = trim( command( "forgebox whoami" ).run( returnOutput = true ) );
			} catch ( any ignoredException ) {
				forgeBoxUser = "";
			}
			if ( !len( forgeBoxUser ) || forgeBoxUser contains "not logged in" ) {
				report( false, "ForgeBox", "not signed in", "Run: box forgebox login" );
			} else {
				report( true, "ForgeBox", "signed in" );
			}
		} else {
			report( true, "ForgeBox", "not needed (publish.forgebox is false)" );
		}
	}

	/**
	 * Checks the test server when the build is configured to run tests.
	 */
	private function checkServer(){
		print.line().boldLine( "Test server" ).toConsole();

		if ( !variables.settings.runTests ) {
			report( true, "test server", "not needed (runTests is false)" );
			return;
		}

		var probeUrl   = variables.config.probeUrl();
		var statusCode = probe( probeUrl, 15 );

		if ( statusCode >= 200 && statusCode < 400 ) {
			report( true, "test server", "answering at #probeUrl# (status #statusCode#)" );
		} else {
			report(
				false,
				"test server",
				"no answer at #probeUrl#",
				"Start a server, such as: box server start  (or set runTests to false in release.json)"
			);
		}
	}

	// REPORT OUTPUT

	/**
	 * Prints one check result and counts failed checks.
	 *
	 * @passed  True when the check passed.
	 * @label   The item that was checked.
	 * @detail  The check result.
	 * @fix     Instructions shown after a failed check. Use an array for several lines.
	 */
	private function report( required boolean passed, required string label, string detail = "", any fix = "" ){
		if ( arguments.passed ) {
			print.greenLine( "  ok    #arguments.label#: #arguments.detail#" ).toConsole();
			return;
		}
		variables.problems = ( variables.problems ?: 0 ) + 1;
		print.boldRedLine( "  FIX   #arguments.label#: #arguments.detail#" ).toConsole();
		var fixLines = isArray( arguments.fix ) ? arguments.fix : ( len( arguments.fix ) ? [ arguments.fix ] : [] );
		for ( var index = 1; index <= arrayLen( fixLines ); index++ ) {
			print.yellowLine( ( index == 1 ? "        -> " : "           " ) & fixLines[ index ] ).toConsole();
		}
	}

	/** Returns "yes" for true and "no" for false. */
	private string function yesNo( required boolean value ){
		return arguments.value ? "yes" : "no";
	}
}
