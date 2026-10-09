/**
 * Loads and checks one project's release settings.
 *
 * A command finds the project root and calls load( root ). This component reads release.json,
 * uses default values for missing settings, and gets values from box.json when needed. It
 * checks the final settings and provides project paths and access to git and gh commands.
 *
 * Projects change release behavior through release.json. They never edit the module.
 */
component {

	property name="locator"         inject="ProjectLocator@commandbox-release";
	property name="processRunner"   inject="ProcessRunner@commandbox-release";
	property name="versionService"  inject="VersionService@commandbox-release";
	property name="projectSettings" inject="ProjectSettingsService@commandbox-release";

	function init(){
		variables.root        = "";
		variables.configPath  = "";
		variables.touchedKeys = {};
		variables.settings    = {};
		return this;
	}

	/**
	 * Reads and checks the settings for one project.
	 *
	 * @root The project root folder that contains box.json.
	 */
	function load( required string root ){
		variables.root        = reReplace( replace( arguments.root, "\", "/", "all" ), "/+$", "" );
		variables.configPath  = variables.locator.configFile( variables.root );
		variables.touchedKeys = {};
		variables.settings    = loadSettings();
		return this;
	}

	/** Returns all project settings. */
	struct function getSettings(){
		return variables.settings;
	}

	/**
	 * Returns one project setting.
	 *
	 * @key          The setting name, such as "branch".
	 * @defaultValue The value to return when the setting is missing.
	 */
	function get( required string key, defaultValue = "" ){
		return structKeyExists( variables.settings, arguments.key ) ? variables.settings[ arguments.key ] : arguments.defaultValue;
	}

	/**
	 * Converts a project-relative path to a full path.
	 *
	 * @relative A project-relative path, such as "CHANGELOG.md".
	 */
	string function repoPath( required string relative ){
		return variables.root & "/" & arguments.relative;
	}

	/** Returns the full project root path. */
	string function getRoot(){
		return variables.root;
	}

	/** Returns the settings file path or an empty string when no file exists. */
	string function configPath(){
		return variables.configPath;
	}

	/** Returns the installed module version or an empty string when it cannot be read. */
	string function moduleVersion(){
		try {
			return trim( deserializeJSON( fileRead( expandPath( "/commandbox-release/box.json" ) ) ).version ?: "" );
		} catch ( any ignoredException ) {
			return "";
		}
	}

	/** Reads and returns the box.json data for the project. */
	struct function boxJSON(){
		var path = repoPath( "box.json" );
		if ( !fileExists( path ) ) {
			throw( type = "Release.Config", message = "No box.json file was found at #path#. Run release commands inside a CommandBox project." );
		}
		return deserializeJSON( fileRead( path ) );
	}

	/** Returns the box.json slug. It uses the package name when the slug is missing. */
	string function slug(){
		var box = boxJSON();
		return box.slug ?: ( box.name ?: "package" );
	}

	/** Returns the version from box.json. */
	string function version(){
		return boxJSON().version ?: "0.0.0";
	}

	/**
	 * Returns the box.json ignore list as an array of patterns. Returns an empty array if the
	 * list is missing or invalid. ForgeBox treats those cases the same way.
	 */
	array function packageIgnores(){
		var packageData = {};
		try {
			packageData = boxJSON();
		} catch ( any ignoredException ) {
			return [];
		}
		var ignore = packageData.ignore ?: [];
		if ( !isArray( ignore ) ) {
			return [];
		}
		var patterns = [];
		for ( var item in ignore ) {
			if ( isSimpleValue( item ) && len( trim( item ) ) ) {
				patterns.append( trim( item ) );
			}
		}
		return patterns;
	}

	/**
	 * Runs git, gh, or another program in the project root. It returns the exit code and output
	 * instead of throwing an exception. See ProcessRunner.
	 *
	 * @name The program name, such as "git".
	 * @args The argument list, such as [ "status", "--porcelain" ].
	 */
	struct function execNative( required string name, array args = [] ){
		return variables.processRunner.run( arguments.name, arguments.args, variables.root );
	}

	/** Returns the URL of the release remote, or an empty string when Git has no remote with that name. */
	string function remoteUrl(){
		var result = execNative( "git", [ "remote", "get-url", variables.settings.remote ] );
		return result.exitCode == 0 ? trim( result.output ) : "";
	}

	/** Returns OWNER/REPO when the release remote is on github.com. Otherwise returns an empty string. */
	string function gitHubRepo(){
		return variables.projectSettings.gitHubRepo( remoteUrl() );
	}

	/** Returns true when a program can be found and started. */
	boolean function commandExists( required string name ){
		return variables.processRunner.commandExists( arguments.name );
	}

	/** Returns a program's full path or its original name when no file is found. */
	string function findBinary( required string name ){
		return variables.processRunner.findBinary( arguments.name );
	}

	/**
	 * Returns the site root URL used to check the test server. It does not return the test
	 * runner URL because requesting that URL would start all tests.
	 */
	string function probeUrl(){
		return reReplaceNoCase( variables.settings.testRunner, "^(https?://[^/]+).*$", "\1" ) & "/";
	}

	// SETTINGS

	/**
	 * Creates the final settings. It starts with defaults, applies file values, and checks the
	 * result.
	 */
	private struct function loadSettings(){
		var result = defaults();

		if ( len( variables.configPath ) && fileExists( variables.configPath ) ) {
			var settingsText = trim( fileRead( variables.configPath ) );
			if ( len( settingsText ) ) {
				var userSettings = "";
				try {
					userSettings = deserializeJSON( settingsText );
				} catch ( any exception ) {
					throw(
						type    = "Release.Config",
						message = "release.json has invalid JSON: #exception.message#. "
							& "Check for values without quotes, extra commas, and single backslashes. "
							& "JSON requires two backslashes for one backslash."
					);
				}
				if ( !isStruct( userSettings ) ) {
					throw( type = "Release.Config", message = "release.json must contain a JSON object, such as { ""branch"": ""main"" }." );
				}
				rejectOldKeys( userSettings );
				result = merge( result, userSettings );
			}
		}

		applyForgeBoxDefault( result );
		fillDerivedDefaults( result );
		validate( result );
		return result;
	}

	/**
	 * Returns the settings used when release.json does not provide a value.
	 */
	private struct function defaults(){
		return {
			"requires"         : "",
			"branch"           : "main",
			"changelog"        : "CHANGELOG.md",
			// An empty value uses testbox.runner from box.json or the default local URL.
			"testRunner"       : "",
			"runTests"         : true,
			"remote"           : "origin",
			"gitSync"          : true,
			"requireCleanTree" : true,
			"coldboxMapping"   : "test-harness/coldbox",
			"stagingDir"       : ".tmp",
			"artifactsDir"     : ".artifacts",
			"tagPrefix"        : "v",
			"publish"          : { "forgebox" : true, "github" : true },
			"engines"          : [],
			"warmup"           : { "attempts" : 60, "delaySeconds" : 5 }
		};
	}

	/**
	 * Stops if release.json has a setting from build-template 1.x or 2.x. The command cannot
	 * convert the old setting, so it tells the user what to change.
	 */
	private void function rejectOldKeys( required struct userSettings ){
		for ( var oldKey in [ "minimumKitVersion", "excludes", "excludesAdd", "templateVersion" ] ) {
			if ( structKeyExists( arguments.userSettings, oldKey ) ) {
				throw(
					type    = "Release.Config",
					message = "release.json has the old setting ""#oldKey#"". commandbox-release 3.0 does not use it. "
						& "See the README section ""Upgrading from 1.x or 2.x"". Package exclusions now live in the box.json ignore list."
				);
			}
		}
	}

	/**
	 * Sets the default for publish.forgebox when release.json does not set it. A module
	 * publishes to ForgeBox by default. Any other project does not.
	 */
	private void function applyForgeBoxDefault( required struct settings ){
		if ( userTouched( "publish.forgebox" ) ) {
			return;
		}
		var packageData = {};
		try {
			packageData = boxJSON();
		} catch ( any ignoredException ) {
			packageData = {};
		}
		arguments.settings.publish.forgebox = variables.projectSettings.isModule(
			packageData,
			fileExists( repoPath( "ModuleConfig.cfc" ) )
		);
	}

	/**
	 * Fills settings that can be read from the project. The current derived setting is the test
	 * runner URL from testbox.runner in box.json.
	 */
	private void function fillDerivedDefaults( required struct settings ){
		if ( len( trim( arguments.settings.testRunner ) ) ) {
			return;
		}
		var packageData = {};
		try {
			packageData = boxJSON();
		} catch ( any ignoredException ) {
			packageData = {};
		}
		arguments.settings.testRunner = variables.projectSettings.detectTestRunner( packageData );
	}

	/**
	 * Applies one struct over another. It combines nested structs one key at a time. For example,
	 * setting only publish.github keeps the default publish.forgebox value. An array replaces
	 * the full default array so settings do not contain an unexpected mix of both lists.
	 */
	private struct function merge( required struct base, required struct overlay ){
		var result = duplicate( arguments.base );
		for ( var key in arguments.overlay ) {
			var incoming = arguments.overlay[ key ];
			if (
				structKeyExists( result, key )
				&& isStruct( result[ key ] )
				&& isStruct( incoming )
			) {
				result[ key ] = merge( result[ key ], incoming );
				for ( var sub in incoming ) {
					variables.touchedKeys[ key & "." & sub ] = true;
				}
			} else {
				result[ key ] = incoming;
				variables.touchedKeys[ key ] = true;
			}
		}
		return result;
	}

	/** Returns true when the settings file provided a key. */
	private boolean function userTouched( required string key ){
		return structKeyExists( variables.touchedKeys, arguments.key );
	}

	/** Checks every setting after defaults and project values are applied. */
	private void function validate( required struct settings ){
		validateProjectSettings( arguments.settings );
		validateFolderSettings( arguments.settings );
		validatePublishSettings( arguments.settings );
		validateEngineSettings( arguments.settings );
		validateWarmupSettings( arguments.settings );
		validateTestRunner( arguments.settings );
		validateRequiredVersion( arguments.settings );
	}

	private void function validateProjectSettings( required struct settings ){
		if ( !len( trim( arguments.settings.branch ) ) ) {
			throw( type = "Release.Config", message = "release.json branch cannot be empty. Enter the release branch, such as ""main""." );
		}
		if ( !len( trim( arguments.settings.changelog ) ) ) {
			throw( type = "Release.Config", message = "release.json changelog cannot be empty. Enter the changelog filename, such as ""CHANGELOG.md""." );
		}
		// Git reads a name that starts with "-" as an option, so the first character must not be "-".
		if ( !isSimpleValue( arguments.settings.remote ) || !reFind( "^[A-Za-z0-9._][A-Za-z0-9._-]*$", arguments.settings.remote ) ) {
			throw( type = "Release.Config", message = "release.json remote must be a Git remote name, such as ""origin""." );
		}
		if ( !isBoolean( arguments.settings.runTests ) ) {
			throw( type = "Release.Config", message = "release.json runTests must be true or false." );
		}
	}

	/**
	 * Checks the build folders. The build deletes these folders before each run, so each one
	 * must be a subfolder of the project root. An empty value, ".", an absolute path, or a ".."
	 * segment could point the delete at the project itself or at a folder outside it.
	 */
	private void function validateFolderSettings( required struct settings ){
		for ( var key in [ "stagingDir", "artifactsDir" ] ) {
			var value = arguments.settings[ key ];
			var clean = isSimpleValue( value ) ? reReplace( replace( trim( value ), "\", "/", "all" ), "/+$", "" ) : "";
			if (
				!len( clean )
				|| reFind( "^/|^[A-Za-z]:", clean )
				|| arrayFind( listToArray( clean, "/" ), "." )
				|| arrayFind( listToArray( clean, "/" ), ".." )
			) {
				throw(
					type    = "Release.Config",
					message = "release.json #key# must be a folder inside the project, such as "".tmp"". "
						& "The build deletes this folder before each run."
				);
			}
		}
	}

	private void function validatePublishSettings( required struct settings ){
		if (
			!isStruct( arguments.settings.publish )
			|| !structKeyExists( arguments.settings.publish, "forgebox" )
			|| !structKeyExists( arguments.settings.publish, "github" )
		) {
			throw( type = "Release.Config", message = "release.json publish must look like { ""forgebox"": true, ""github"": true }." );
		}
		if ( !isBoolean( arguments.settings.publish.forgebox ) || !isBoolean( arguments.settings.publish.github ) ) {
			throw( type = "Release.Config", message = "release.json publish.forgebox and publish.github must be true or false." );
		}
	}

	private void function validateEngineSettings( required struct settings ){
		if ( !isArray( arguments.settings.engines ) ) {
			throw(
				type    = "Release.Config",
				message = "release.json engines must be an array like "
					& "[ { ""name"": ""Lucee 5"", ""configFile"": ""server-lucee@5.json"" } ]."
			);
		}
		for ( var engine in arguments.settings.engines ) {
			if ( !isStruct( engine ) || !structKeyExists( engine, "configFile" ) ) {
				throw(
					type    = "Release.Config",
					message = "Each release.json engine needs a configFile, such as "
						& "{ ""name"": ""Lucee 5"", ""configFile"": ""server-lucee@5.json"" }."
				);
			}
		}
	}

	private void function validateWarmupSettings( required struct settings ){
		if (
			!isStruct( arguments.settings.warmup )
			|| !isNumeric( arguments.settings.warmup.attempts ?: "" )
			|| !isNumeric( arguments.settings.warmup.delaySeconds ?: "" )
		) {
			throw( type = "Release.Config", message = "release.json warmup must look like { ""attempts"": 60, ""delaySeconds"": 5 }." );
		}
	}

	private void function validateTestRunner( required struct settings ){
		if ( !reFindNoCase( "^https?://", arguments.settings.testRunner ) ) {
			throw(
				type    = "Release.Config",
				message = "release.json testRunner must be a full URL, such as "
					& """http://127.0.0.1:60310/tests/runner.cfm""."
			);
		}
	}

	/**
	 * Stops if the project requires a newer module version. This keeps release commands on the
	 * required version across computers.
	 */
	private void function validateRequiredVersion( required struct settings ){
		var required  = trim( arguments.settings.requires ?: "" );
		var installed = moduleVersion();
		if ( !len( required ) || !len( installed ) ) {
			return;
		}
		if ( variables.versionService.compareVersions( installed, required ) < 0 ) {
			throw(
				type    = "Release.TooOld",
				message = "This project requires commandbox-release #required# or newer. The installed version is #installed#. "
					& "Run: box update commandbox-release --system"
			);
		}
	}
}
