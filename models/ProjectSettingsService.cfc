/**
 * Calculates project settings used by ProjectConfig.cfc and ProjectInstaller.cfc.
 *
 * This component does not read or write files. Callers provide parsed JSON data and filenames.
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
	 * Returns the first test runner URL from box.json. It returns the default local URL when
	 * box.json does not contain one.
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
			: "http://127.0.0.1:60299/tests/runner.cfm";
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
				"/node_modules/",
				"/resources/",
				"/package.json",
				"/package-lock.json",
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
