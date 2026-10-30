/**
 * Calculates project settings used by ProjectConfig.cfc and ProjectInstaller.cfc.
 *
 * This component does not read or write files or run Git. Callers provide parsed JSON data
 * and filenames.
 */
component {

	/**
	 * Returns true when the project is an installable module. The box.json type must be a
	 * module type, or the project root must contain ModuleConfig.cfc.
	 *
	 * @packageData     The parsed box.json.
	 * @hasModuleConfig True when ModuleConfig.cfc is in the project root.
	 */
	boolean function isModule( required struct packageData, boolean hasModuleConfig = false ){
		var packageType = lCase( arguments.packageData.type ?: "" );
		var moduleTypes = "modules,commandbox-modules,cachebox-modules,logbox-modules,wirebox-modules,plugins,interceptors";
		return arguments.hasModuleConfig || listFindNoCase( moduleTypes, packageType ) > 0;
	}

	/**
	 * Returns the first test runner URL or path from box.json. It returns "/tests/runner.cfm"
	 * when box.json does not contain one. That is the default of `box testbox run`.
	 */
	string function detectTestRunner( required struct packageData ){
		var configuredRunner = arguments.packageData.testbox.runner ?: "";

		if ( isArray( configuredRunner ) && arrayLen( configuredRunner ) ) {
			configuredRunner = isStruct( configuredRunner[ 1 ] )
				? ( configuredRunner[ 1 ].default ?: "" )
				: configuredRunner[ 1 ];
		} else if ( isStruct( configuredRunner ) ) {
			for ( var runnerName in configuredRunner ) {
				configuredRunner = configuredRunner[ runnerName ];
				break;
			}
		}

		return isSimpleValue( configuredRunner ) && len( trim( configuredRunner ) )
			? trim( configuredRunner )
			: "/tests/runner.cfm";
	}

	/**
	 * Returns the test command that `release init` suggests, or an empty string. It suggests
	 * "run-script test" for a CommandBox module that has a test script and no TestBox runner
	 * URL. Such a module runs its specs inside CommandBox, without a web server.
	 *
	 * @packageData The parsed box.json.
	 */
	string function detectTestCommand( required struct packageData ){
		var packageType = lCase( arguments.packageData.type ?: "" );
		var testScript  = arguments.packageData.scripts.test ?: "";
		var runner      = arguments.packageData.testbox.runner ?: "";
		var hasRunner   = !isSimpleValue( runner ) || len( trim( runner ) );
		if ( packageType == "commandbox-modules" && isSimpleValue( testScript ) && len( trim( testScript ) ) && !hasRunner ) {
			return "run-script test";
		}
		return "";
	}

	/**
	 * Returns the box.json ignore patterns that `release init` recommends for a module or a
	 * web app.
	 *
	 * The patterns follow box.json ignore rules. A leading / matches only the project root.
	 * Without /, the pattern matches at any folder depth. A leading ! puts back a file that
	 * an earlier pattern left out.
	 *
	 * @isModule True for an installable module. See isModule().
	 */
	array function recommendedIgnores( required boolean isModule ){
		var shared = [
			"/tests/",
			"/test-harness/",
			"/test-results/",
			"/temp/",
			"/plans/",
			"/server*.json",
			"/*.code-workspace",
			"/AGENTS.md",
			"/CLAUDE.md",
			"/DEVNOTES.md",
			"/RELEASE.md",
			"/node_modules/",
			"/package.json",
			"/package-lock.json",
			"**/*.bak",
			"**/*.zip",
			"**/*.tar",
			"**/*.tar.gz",
			"**/*.tgz",
			"**/*.7z",
			"**/*.rar"
		];

		if ( arguments.isModule ) {
			var moduleIgnores = [
				"**/.*",
				"/build/",
				"/modules/",
				"/resources/",
				"/webpack.config.js",
				"/vite.config.js",
				"/vitest.config.js",
				"/docker-compose.yml"
			];
			moduleIgnores.append( shared, true );
			return moduleIgnores;
		}

		// A web app keeps .htaccess and .well-known because servers read them.
		var appIgnores = [ "**/.*", "!/.htaccess", "!/.well-known/" ];
		appIgnores.append( shared, true );
		return appIgnores;
	}

	/**
	 * Adds patterns that are not already in the ignore list. Keeps the existing order. Returns
	 * the full list and the patterns it added.
	 *
	 * @existing  The current box.json ignore value. A missing or invalid value counts as empty.
	 * @additions The patterns to add when they are missing.
	 */
	struct function mergeIgnores( any existing = [], array additions = [] ){
		var combined = [];
		if ( isArray( arguments.existing ) ) {
			for ( var item in arguments.existing ) {
				combined.append( item );
			}
		}

		var present = {};
		for ( var item in combined ) {
			if ( isSimpleValue( item ) ) {
				present[ trim( item ) ] = true;
			}
		}

		var added = [];
		for ( var pattern in arguments.additions ) {
			if ( !structKeyExists( present, pattern ) ) {
				combined.append( pattern );
				added.append( pattern );
				present[ pattern ] = true;
			}
		}

		return { "ignore" : combined, "added" : added };
	}

	/**
	 * Returns the box.json install scripts that run `package set ignore`. CommandBox runs
	 * install scripts such as postInstall after `box install`, so such a script empties the
	 * ignore list that `release init` fills. Each result is a struct with name and template.
	 * template is true only for the postInstall script from the ColdBox app template:
	 *
	 * pathExists .env || cp .env.example .env && package set ignore=[]
	 *
	 * CommandBox runs that chain from left to right. The last command runs whether or not .env
	 * exists. A script with extra spaces still counts as the template script. A script that is
	 * not a string, such as an array of commands, is skipped.
	 *
	 * @packageData The parsed box.json.
	 */
	array function ignoreClearingScripts( required struct packageData ){
		var found   = [];
		var scripts = arguments.packageData.scripts ?: "";
		if ( !isStruct( scripts ) ) {
			return found;
		}

		var templateScript = "pathExists .env || cp .env.example .env && package set ignore=[]";
		var names          = structKeyArray( scripts );
		names.sort( "textnocase" );
		for ( var name in names ) {
			var script = scripts[ name ] ?: "";
			if ( !findNoCase( "install", name ) || !isSimpleValue( script ) ) {
				continue;
			}
			script = trim( reReplace( script, "\s+", " ", "all" ) );
			if ( !reFindNoCase( "package set ignore", script ) ) {
				continue;
			}
			found.append( {
				"name"     : name,
				"template" : name == "postInstall" && compare( script, templateScript ) == 0
			} );
		}
		return found;
	}

	/**
	 * Returns a display name for one CommandBox server configuration.
	 */
	string function engineName( required string fileName, struct serverSettings = {} ){
		if (
			structKeyExists( arguments.serverSettings, "app" )
			&& isStruct( arguments.serverSettings.app )
			&& structKeyExists( arguments.serverSettings.app, "cfengine" )
			&& isSimpleValue( arguments.serverSettings.app.cfengine )
			&& len( trim( arguments.serverSettings.app.cfengine ) )
		) {
			return readableEngineName( trim( arguments.serverSettings.app.cfengine ) );
		}

		if (
			structKeyExists( arguments.serverSettings, "name" )
			&& isSimpleValue( arguments.serverSettings.name )
			&& len( trim( arguments.serverSettings.name ) )
		) {
			return trim( arguments.serverSettings.name );
		}

		var filenameStem = reReplaceNoCase( arguments.fileName, "^server-?", "" );
		filenameStem     = reReplaceNoCase( filenameStem, "\.json$", "" );
		return len( trim( filenameStem ) ) ? readableEngineName( filenameStem ) : "Server";
	}

	/**
	 * Converts an engine ID or filename without its extension into a display name.
	 */
	string function readableEngineName( required string value ){
		var readableName = reReplaceNoCase( arguments.value, "[-_]cfml\b", "" );
		readableName     = replace( readableName, "@", " ", "all" );
		readableName     = replace( readableName, "-", " ", "all" );

		var words = listToArray( readableName, " " );
		for ( var index = 1; index <= arrayLen( words ); index++ ) {
			words[ index ] = uCase( left( words[ index ], 1 ) )
				& mid( words[ index ], 2, len( words[ index ] ) );
		}
		return arrayToList( words, " " );
	}
}
