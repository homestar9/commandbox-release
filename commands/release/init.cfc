/**
 * Sets up the current project for commandbox-release.
 * .
 * It asks where to publish the project and whether to run tests before each release. For a
 * CommandBox module with a test script, it suggests the test command "run-script test". It
 * creates release.json and, if needed, CHANGELOG.md. It also adds common patterns to the
 * box.json ignore list so development files stay out of the package. Existing files stay in
 * place unless you use --force.
 * .
 * Run this command again to add missing ignore patterns. Without --force, setup keeps
 * existing release.json and changelog files. When release.json exists, setup skips the
 * setup questions unless you use --force.
 * .
 * Use --yes to accept the default answers without questions, such as in a script.
 * .
 * {code:bash}
 * release init
 * release init --yes
 * release init --docs --ci
 * release init --force
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	property name="projectSettings" inject="ProjectSettingsService@commandbox-release";

	/**
	 * @yes   Accepts every default without asking.
	 * @force Replaces release.json and CHANGELOG.md when they already exist.
	 * @docs  Copies the RELEASE.md guide to the project root.
	 * @ci    Copies the GitHub Actions workflow to .github/workflows/release.yml.
	 */
	function run(
		boolean yes   = false,
		boolean force = false,
		boolean docs  = false,
		boolean ci    = false
	){
		var args = arguments;
		guard( function(){
			var root    = findOrCreateProject( args.yes );
			var answers = collectAnswers( root, args.yes, args.force );
			service( "ProjectInstaller" ).run(
				root    = root,
				answers = answers,
				force   = args.force,
				docs    = args.docs,
				ci      = args.ci
			);
		} );
	}

	// QUESTIONS

	/**
	 * Returns the project root. If the current folder has no box.json, it offers to create one
	 * with `package init`.
	 */
	private string function findOrCreateProject( required boolean yes ){
		try {
			return variables.locator.findRoot( getCWD() );
		} catch ( any exception ) {
			if ( ( exception.type ?: "" ) != "Release.NoProject" ) {
				rethrow;
			}
		}

		var root = reReplace( replace( getCWD(), "\", "/", "all" ), "/+$", "" );
		print.line( "No box.json was found in #root#." ).toConsole();
		if ( !arguments.yes && !askYesNo( "Create one now?", true ) ) {
			return error( "A project needs box.json. Create it with: package init" );
		}

		var folderName = listLast( root, "/" );
		var slug       = lCase( reReplace( folderName, "[^A-Za-z0-9]+", "-", "all" ) );
		command( "package init" )
			.params(
				name    = folderName,
				slug    = slug,
				version = "1.0.0"
			)
			.inWorkingDirectory( root & "/" )
			.run();
		print.greenLine( "  create  box.json" ).toConsole();
		return root;
	}

	/**
	 * Collects answers for the release.json settings file. If release.json exists and --force
	 * is not used, setup keeps the file. The questions are skipped because setup will not use
	 * the answers to change that file.
	 */
	private struct function collectAnswers( required string root, required boolean yes, required boolean force ){
		var packageData = deserializeJSON( fileRead( arguments.root & "/box.json" ) );
		var isModule    = variables.projectSettings.isModule( packageData, fileExists( arguments.root & "/ModuleConfig.cfc" ) );
		var testRunner  = variables.projectSettings.detectTestRunner( packageData );
		var testCommand = variables.projectSettings.detectTestCommand( packageData );
		var answers     = {
			"forgebox"    : isModule,
			"github"      : true,
			"runTests"    : true,
			"testCommand" : testCommand,
			"testRunner"  : testRunner
		};

		if ( arguments.yes ) {
			return answers;
		}
		if ( fileExists( arguments.root & "/release.json" ) && !arguments.force ) {
			print.line().line( "release.json already exists. Setup will keep release.json and add missing ignore patterns." ).toConsole();
			return answers;
		}

		if ( isModule ) {
			print.line().line( "box.json describes a module. Modules usually publish to ForgeBox and GitHub." ).toConsole();
		} else {
			print.line().line( "box.json does not describe a module. Web apps usually publish to GitHub only." ).toConsole();
		}
		answers.forgebox = askYesNo( "Publish to ForgeBox?", isModule );
		answers.github   = askYesNo( "Create GitHub Releases?", true );
		answers.runTests = askYesNo( "Run the tests before every release?", true );
		if ( answers.runTests && len( testCommand ) ) {
			print.line( "This module has a test script. A test command runs it with box, without a server." ).toConsole();
			answers.testCommand = trim( ask( message = "Test command (leave blank to use a test runner URL): ", defaultResponse = testCommand ) );
		}
		if ( answers.runTests && !len( answers.testCommand ) ) {
			var runnerAnswer = trim( ask( message = "Test runner URL or path: ", defaultResponse = testRunner ) );
			answers.testRunner = len( runnerAnswer ) ? runnerAnswer : testRunner;
		}
		return answers;
	}
}
