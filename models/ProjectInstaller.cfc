/**
 * Sets up a project for commandbox-release.
 *
 * `box release init` creates release.json from the user's answers and project settings. It
 * creates a changelog if needed. It adds common package ignore patterns to box.json. Use
 * `--docs` to copy RELEASE.md and `--ci` to copy the GitHub Actions workflow.
 *
 * It keeps existing files unless you use `--force`. It finds default settings in box.json,
 * Git, and server JSON files in the project root.
 */
component extends="commandbox-release.models.BaseService" {

	property name="projectSettings" inject="ProjectSettingsService@commandbox-release";
	property name="processRunner"   inject="ProcessRunner@commandbox-release";

	/**
	 * Runs the setup steps and prints the chosen settings.
	 *
	 * @root    The project root folder.
	 * @answers The user's answers: projectType, forgebox, github, runTests, and testRunner.
	 *          A missing answer uses the value found in the project.
	 * @force   Replaces release.json and the changelog when they already exist.
	 * @docs    Copies the RELEASE.md guide to the project root.
	 * @ci      Copies the GitHub Actions workflow to .github/workflows/release.yml.
	 */
	function run(
		required string root,
		struct answers = {},
		boolean force  = false,
		boolean docs   = false,
		boolean ci     = false
	){
		variables.root = reReplace( replace( arguments.root, "\", "/", "all" ), "/+$", "" );

		print.line().boldLine( "Setting up commandbox-release" ).line( repeatString( "-", 60 ) ).toConsole();

		if ( !fileExists( variables.root & "/box.json" ) ) {
			return stop( "No box.json file was found at #variables.root#. Run this command inside a CommandBox package." );
		}

		var settings = writeReleaseJSON( arguments.answers, arguments.force );
		writeChangelog( arguments.force );
		updatePackageIgnores( settings.projectType );
		updateGitIgnore();
		if ( arguments.docs ) {
			copyTemplate( "RELEASE.md", "RELEASE.md", arguments.force );
		}
		if ( arguments.ci ) {
			copyTemplate( "github-release.yml", ".github/workflows/release.yml", arguments.force );
		}
		noteOldSettings();

		print
			.line( repeatString( "-", 60 ) )
			.boldGreenLine( "Setup complete." )
			.line()
			.boldLine( "Next steps:" )
			.line( "  1. Review release.json and the box.json ignore list." )
			.line( "  2. Add notes under [Unreleased] in #detectChangelogName()#." )
			.line( "  3. Check the release:      box release publish patch --dryRun" )
			.line( "  4. Publish the release:   box release publish patch" )
			.toConsole();
		if ( !arguments.docs ) {
			print.line().line( "Run box release help to see all commands. Use --docs to copy the RELEASE.md guide." ).toConsole();
		}
	}

	// SETUP STEPS

	/**
	 * Creates release.json from the answers and project settings. Returns the new settings, or
	 * the existing settings if the file was kept.
	 */
	private struct function writeReleaseJSON( required struct answers, required boolean force ){
		var path        = variables.root & "/release.json";
		var packageData = deserializeJSON( fileRead( variables.root & "/box.json" ) );
		var projectType = lCase( arguments.answers.projectType ?: variables.projectSettings.detectProjectType( packageData ) );

		if ( fileExists( path ) && !arguments.force ) {
			print.yellowLine( "  skip  release.json already exists. Use --force to replace it." ).toConsole();
			var existing = {};
			try {
				existing = deserializeJSON( fileRead( path ) );
			} catch ( any ignoredException ) {
				existing = {};
			}
			return { "projectType" : lCase( existing.projectType ?: projectType ) };
		}

		var settings = {
			"requires"    : moduleVersion(),
			"projectType" : projectType,
			"branch"      : detectBranch(),
			"changelog"   : detectChangelogName(),
			"testRunner"  : arguments.answers.testRunner ?: variables.projectSettings.detectTestRunner( packageData ),
			"runTests"    : arguments.answers.runTests ?: true,
			"publish"     : {
				"forgebox" : arguments.answers.forgebox ?: ( projectType == "module" ),
				"github"   : arguments.answers.github ?: true
			},
			"engines"     : detectEngines()
		};

		fileWrite( path, formatJSON( settings ) );
		print.greenLine( "  create  release.json" ).toConsole();
		print.line( "        project type:   #settings.projectType#" ).toConsole();
		print.line( "        release branch: #settings.branch#" ).toConsole();
		print.line( "        publish to:     #publishSummary( settings.publish )#" ).toConsole();
		print.line( "        run tests:      #( settings.runTests ? "yes, at " & settings.testRunner : "no" )#" ).toConsole();
		print.line( "        engines found:  #arrayLen( settings.engines )#" ).toConsole();
		return settings;
	}

	/**
	 * Creates a changelog with an [Unreleased] section.
	 */
	private function writeChangelog( required boolean force ){
		var name = detectChangelogName();
		var path = variables.root & "/" & name;

		if ( fileExists( path ) && !arguments.force ) {
			print.yellowLine( "  skip  #name# already exists." ).toConsole();
			return;
		}

		var template = modulePath( "templates/CHANGELOG.md" );
		if ( fileExists( template ) ) {
			fileCopy( template, path );
		} else {
			fileWrite( path, defaultChangelog() );
		}
		print.greenLine( "  create  #name#" ).toConsole();
	}

	/**
	 * Adds common ignore patterns to box.json. Keeps existing patterns in their original order.
	 * Running this step again does not add duplicates.
	 */
	private function updatePackageIgnores( required string projectType ){
		var packagePath = variables.root & "/box.json";
		var packageData = deserializeJSON( fileRead( packagePath ) );
		var outcome     = variables.projectSettings.mergeIgnores(
			packageData.ignore ?: [],
			variables.projectSettings.recommendedIgnores( arguments.projectType )
		);

		if ( !arrayLen( outcome.added ) ) {
			print.greenLine( "  ok      box.json ignore list already has the recommended patterns" ).toConsole();
			return;
		}

		packageData[ "ignore" ] = outcome.ignore;
		fileWrite( packagePath, formatJSON( packageData ) );
		print.greenLine( "  update  box.json ignore list (#arrayLen( outcome.added )# pattern#( arrayLen( outcome.added ) == 1 ? "" : "s" )# added)" ).toConsole();
		for ( var pattern in outcome.added ) {
			print.line( "          + #pattern#" ).toConsole();
		}
		print.line( "          These patterns leave files out of the package. Edit the list in box.json." ).toConsole();
	}

	/**
	 * Adds the build folders to .gitignore so Git does not list build files as untracked. It
	 * creates .gitignore if needed and keeps its existing lines.
	 */
	private function updateGitIgnore(){
		var path     = variables.root & "/.gitignore";
		var existing = fileExists( path ) ? fileRead( path ) : "";
		var lines    = listToArray( replace( existing, chr( 13 ), "", "all" ), chr( 10 ), true );
		var present  = {};
		for ( var line in lines ) {
			present[ trim( line ) ] = true;
		}

		var added = [];
		for ( var folder in [ ".tmp/", ".artifacts/" ] ) {
			if ( !structKeyExists( present, folder ) && !structKeyExists( present, left( folder, len( folder ) - 1 ) ) ) {
				added.append( folder );
			}
		}
		if ( !arrayLen( added ) ) {
			return;
		}

		var lf      = chr( 10 );
		var content = existing;
		if ( len( content ) && right( content, 1 ) != lf ) {
			content &= lf;
		}
		content &= ( len( content ) ? lf : "" ) & "## commandbox-release build output" & lf & arrayToList( added, lf ) & lf;
		fileWrite( path, content );
		print.greenLine( "  update  .gitignore (#arrayToList( added, ", " )#)" ).toConsole();
	}

	/**
	 * Copies one template from the module into the project.
	 *
	 * @templateName The filename under templates/.
	 * @relative     The destination path relative to the project root.
	 * @force        Replaces the destination when it already exists.
	 */
	private function copyTemplate( required string templateName, required string relative, required boolean force ){
		var source = modulePath( "templates/" & arguments.templateName );
		var target = variables.root & "/" & arguments.relative;

		if ( !fileExists( source ) ) {
			return;
		}
		if ( fileExists( target ) && !arguments.force ) {
			print.yellowLine( "  skip  #arguments.relative# already exists." ).toConsole();
			return;
		}
		var targetDir = getDirectoryFromPath( target );
		if ( !directoryExists( targetDir ) ) {
			directoryCreate( targetDir, true, true );
		}
		fileCopy( source, target );
		print.greenLine( "  create  #arguments.relative#" ).toConsole();
	}

	/**
	 * Points out settings files from build-template 1.x and 2.x. They are no longer read.
	 */
	private function noteOldSettings(){
		for ( var oldFile in [ "build.json", "build/build.json" ] ) {
			if ( fileExists( variables.root & "/" & oldFile ) ) {
				print
					.line()
					.yellowLine( "#oldFile# is an old settings file. commandbox-release does not read it." )
					.yellowLine( "Copy custom settings to release.json, then delete #oldFile#. See ""Upgrading from 1.x or 2.x"" in the README." )
					.toConsole();
			}
		}
	}

	// PROJECT DETECTION

	/**
	 * Returns Gitflow's production branch when it is configured. Otherwise, it asks Git for the
	 * current branch. This works in linked worktrees. It returns main for a detached checkout
	 * or when Git cannot provide a branch.
	 */
	private string function detectBranch(){
		var production = variables.processRunner.run( "git", [ "config", "--get", "gitflow.branch.master" ], variables.root );
		if ( production.exitCode == 0 && len( trim( production.output ) ) ) {
			return trim( production.output );
		}

		var current = variables.processRunner.run( "git", [ "symbolic-ref", "--quiet", "--short", "HEAD" ], variables.root );
		if ( current.exitCode == 0 && len( trim( current.output ) ) ) {
			return trim( current.output );
		}
		return "main";
	}

	/**
	 * Returns the exact filename of an existing changelog. It returns CHANGELOG.md when no
	 * changelog exists.
	 *
	 * It reads the directory instead of checking possible names with fileExists(). Windows and
	 * macOS may report that changelog.md exists when the real name is CHANGELOG.md. That wrong
	 * letter case can fail on Linux.
	 */
	private string function detectChangelogName(){
		for ( var name in directoryList( variables.root, false, "name", "*.md" ) ) {
			if ( reFindNoCase( "^changelog\.md$", name ) ) {
				return name;
			}
		}
		return "CHANGELOG.md";
	}

	/**
	 * Finds server JSON files in the project root and creates an engine entry for each file.
	 */
	private array function detectEngines(){
		var engines = [];
		var files   = directoryList( variables.root, false, "name", "*.json" )
			.filter( function( file ){
				return reFindNoCase( "^server(?:-.*)?\.json$", file );
			} );
		files.sort( "textnocase" );

		for ( var file in files ) {
			engines.append( { "name" : engineName( file ), "configFile" : file } );
		}
		return engines;
	}

	/**
	 * Reads one server file and gets its display name from ProjectSettingsService. An invalid
	 * server file still gets an entry with a name based on its filename.
	 */
	private string function engineName( required string file ){
		var serverSettings = {};
		try {
			var parsedSettings = deserializeJSON( fileRead( variables.root & "/" & arguments.file ) );
			serverSettings = isStruct( parsedSettings ) ? parsedSettings : {};
		} catch ( any ignoredException ) {
			// The server command will report the invalid JSON when it starts this server.
		}

		return variables.projectSettings.engineName( arguments.file, serverSettings );
	}

	/** Returns a short description of the publish targets. */
	private string function publishSummary( required struct publish ){
		var targets = [];
		if ( arguments.publish.forgebox ) {
			targets.append( "ForgeBox" );
		}
		if ( arguments.publish.github ) {
			targets.append( "GitHub Releases" );
		}
		return arrayLen( targets ) ? arrayToList( targets, " and " ) : "nowhere (zip file only)";
	}

	/**
	 * Returns a basic changelog when the template file is missing.
	 */
	private string function defaultChangelog(){
		var lf = chr( 10 );
		// Build Markdown headings with chr( 35 ). A # starts a CFML variable, so a literal # in
		// a string must be doubled. chr( 35 ) makes the number of heading marks clear.
		var h1 = repeatString( chr( 35 ), 1 ) & " ";
		var h2 = repeatString( chr( 35 ), 2 ) & " ";
		var h3 = repeatString( chr( 35 ), 3 ) & " ";

		return h1 & "Changelog" & lf & lf
			& "This file lists the important changes to this project." & lf & lf
			& "The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)." & lf
			& "Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)." & lf & lf
			& h2 & "[Unreleased]" & lf & lf
			& h3 & "Added" & lf & lf
			& "- Add changes here while you work." & lf;
	}
}
