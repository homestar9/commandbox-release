/**
 * Sets up the current project for commandbox-release.
 * .
 * It asks where to publish the project and whether to run tests before each release. It
 * creates release.json and, if needed, CHANGELOG.md. It also adds common patterns to the
 * box.json ignore list so development files stay out of the package. Existing files stay in
 * place unless you use --force.
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
			var answers = collectAnswers( root, args.yes );
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
	 * Collects the answers that ProjectInstaller writes into release.json.
	 */
	private struct function collectAnswers( required string root, required boolean yes ){
		var packageData = deserializeJSON( fileRead( arguments.root & "/box.json" ) );
		var isModule    = variables.projectSettings.isModule( packageData, fileExists( arguments.root & "/ModuleConfig.cfc" ) );
		var testRunner  = variables.projectSettings.detectTestRunner( packageData );
		var answers     = {
			"forgebox"   : isModule,
			"github"     : true,
			"runTests"   : true,
			"testRunner" : testRunner
		};

		if ( arguments.yes ) {
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
		if ( answers.runTests ) {
			var runnerAnswer = trim( ask( message = "Test runner URL: ", defaultResponse = testRunner ) );
			answers.testRunner = len( runnerAnswer ) ? runnerAnswer : testRunner;
		}
		return answers;
	}

	/** Asks a yes or no question and returns the answer. */
	private boolean function askYesNo( required string message, required boolean defaultAnswer ){
		var answer = lCase( trim( ask( message = arguments.message & " [y/n] ", defaultResponse = arguments.defaultAnswer ? "y" : "n" ) ) );
		if ( !len( answer ) ) {
			return arguments.defaultAnswer;
		}
		return listFindNoCase( "y,yes,true", answer ) > 0;
	}
}
