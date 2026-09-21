/**
 * Sets up the current project for commandbox-release.
 * .
 * It asks what kind of project this is, where to publish it, and whether to run tests before
 * each release. It creates release.json and, if needed, CHANGELOG.md. It also adds common
 * patterns to the box.json ignore list so development files stay out of the package.
 * Existing files stay in place unless you use --force.
 * .
 * Use --yes to accept the default answers without questions, such as in a script.
 * .
 * {code:bash}
 * release init
 * release init --yes
 * release init type=app --docs --ci
 * release init --force
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	property name="projectSettings" inject="ProjectSettingsService@commandbox-release";

	/**
	 * @type  Use module or app as the project type. Skips the project type question.
	 * @type.options module,app
	 * @yes   Accepts every default without asking.
	 * @force Replaces release.json and CHANGELOG.md when they already exist.
	 * @docs  Copies the RELEASE.md guide to the project root.
	 * @ci    Copies the GitHub Actions workflow to .github/workflows/release.yml.
	 */
	function run(
		string type   = "",
		boolean yes   = false,
		boolean force = false,
		boolean docs  = false,
		boolean ci    = false
	){
		var args = arguments;
		guard( function(){
			var projectType = normaliseType( args.type );
			var root        = findOrCreateProject( projectType, args.yes );
			var answers     = collectAnswers( root, projectType, args.yes );
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
	private string function findOrCreateProject( required string projectType, required boolean yes ){
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

		var chosenType = len( arguments.projectType ) ? arguments.projectType : ( arguments.yes ? "app" : askType( "app" ) );
		variables.chosenType = chosenType;

		var folderName = listLast( root, "/" );
		var slug       = lCase( reReplace( folderName, "[^A-Za-z0-9]+", "-", "all" ) );
		command( "package init" )
			.params(
				name    = folderName,
				slug    = slug,
				version = "1.0.0",
				type    = chosenType == "module" ? "modules" : "projects"
			)
			.inWorkingDirectory( root & "/" )
			.run();
		print.greenLine( "  create  box.json" ).toConsole();
		return root;
	}

	/**
	 * Collects the answers that ProjectInstaller writes into release.json.
	 */
	private struct function collectAnswers( required string root, required string projectType, required boolean yes ){
		var packageData = deserializeJSON( fileRead( arguments.root & "/box.json" ) );
		var detected    = variables.projectSettings.detectProjectType( packageData );
		var chosenType  = arguments.projectType;

		if ( !len( chosenType ) && structKeyExists( variables, "chosenType" ) ) {
			chosenType = variables.chosenType;
		}
		if ( !len( chosenType ) ) {
			chosenType = arguments.yes ? detected : askType( detected );
		}

		var isModule   = chosenType == "module";
		var testRunner = variables.projectSettings.detectTestRunner( packageData );
		var answers    = {
			"projectType" : chosenType,
			"forgebox"    : isModule,
			"github"      : true,
			"runTests"    : true,
			"testRunner"  : testRunner
		};

		if ( arguments.yes ) {
			return answers;
		}

		print.line().line( isModule ? "Modules usually publish to ForgeBox and GitHub." : "Web apps usually publish to GitHub only." ).toConsole();
		answers.forgebox = askYesNo( "Publish to ForgeBox?", isModule );
		answers.github   = askYesNo( "Create GitHub Releases?", true );
		answers.runTests = askYesNo( "Run the tests before every release?", true );
		if ( answers.runTests ) {
			var runnerAnswer = trim( ask( message = "Test runner URL: ", defaultResponse = testRunner ) );
			answers.testRunner = len( runnerAnswer ) ? runnerAnswer : testRunner;
		}
		return answers;
	}

	/** Asks for the project type and returns "module" or "app". */
	private string function askType( required string defaultType ){
		print
			.line()
			.line( "A module publishes a package to ForgeBox and creates a GitHub Release." )
			.line( "A web app creates a GitHub Release with a zip file and does not use ForgeBox." )
			.toConsole();
		for ( var attempt = 1; attempt <= 3; attempt++ ) {
			var answer = normaliseType( ask( message = "Release this project as a module or a web app? [module/app] ", defaultResponse = arguments.defaultType ) );
			if ( len( answer ) ) {
				return answer;
			}
			print.yellowLine( "Enter module or app." ).toConsole();
		}
		return error( "Enter module or app, or use type=module or type=app." );
	}

	/** Asks a yes or no question and returns the answer. */
	private boolean function askYesNo( required string message, required boolean defaultAnswer ){
		var answer = lCase( trim( ask( message = arguments.message & " [y/n] ", defaultResponse = arguments.defaultAnswer ? "y" : "n" ) ) );
		if ( !len( answer ) ) {
			return arguments.defaultAnswer;
		}
		return listFindNoCase( "y,yes,true", answer ) > 0;
	}

	/** Returns "module", "app", or an empty string for anything else. */
	private string function normaliseType( required string value ){
		var cleaned = lCase( trim( arguments.value ) );
		if ( cleaned == "m" || cleaned == "module" || cleaned == "modules" ) {
			return "module";
		}
		if ( cleaned == "a" || cleaned == "app" || cleaned == "application" || cleaned == "web app" || cleaned == "webapp" ) {
			return "app";
		}
		if ( len( cleaned ) ) {
			error( "Unknown type ""#arguments.value#"". Use type=module or type=app." );
		}
		return "";
	}
}
