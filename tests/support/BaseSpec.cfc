/**
 * Sets up shared test helpers. It gets module components from WireBox and finds paths for
 * the repository and temporary projects.
 *
 * tests/Run.cfc loads this working copy before tests run. Therefore,
 * "Name@commandbox-release" refers to this copy.
 */
component extends="testbox.system.BaseSpec" {

	/** Returns a module component with the same WireBox setup used by commands. */
	function model( required string name ){
		return application.wirebox.getInstance( arguments.name & "@commandbox-release" );
	}

	/** Returns component metadata for a module path, such as "commands.release.publish". */
	struct function meta( required string dotPath ){
		return getComponentMetadata( "commandbox-release." & arguments.dotPath );
	}

	/** Returns the repository root with forward slashes and no final slash. */
	string function repoRoot(){
		return reReplace( replace( expandPath( "/commandbox-release" ), "\", "/", "all" ), "/+$", "" );
	}

	/** Returns the module version from its box.json. */
	string function moduleVersion(){
		return deserializeJSON( fileRead( repoRoot() & "/box.json" ) ).version;
	}

	/** Creates an empty folder under .test-work and returns its path. */
	string function createTempProject(){
		var root = repoRoot() & "/.test-work/commandbox-release-spec-" & createUUID();
		directoryCreate( root, true, true );
		return root;
	}

	/**
	 * Deletes a temporary project. Dropbox or antivirus software can briefly lock files on
	 * Windows, so it tries several times. Each test uses a unique folder under .test-work, so
	 * a folder left after failed cleanup will not affect another test.
	 */
	void function deleteDirectory( required string path ){
		if ( !len( arguments.path ) || !directoryExists( arguments.path ) ) {
			return;
		}
		for ( var attempt = 1; attempt <= 5; attempt++ ) {
			try {
				directoryDelete( arguments.path, true );
				return;
			} catch ( any deleteFailure ) {
				sleep( 500 );
			}
		}
	}

	/** Writes a struct to a JSON file. */
	void function writeJSON( required string path, required struct data ){
		fileWrite( arguments.path, serializeJSON( arguments.data ) );
	}

	/** Fails the test with the command output when a process did not exit with 0. */
	void function expectCommand( required struct result, required string label ){
		if ( arguments.result.exitCode != 0 ) {
			throw(
				type    = "Spec.IntegrationCommand",
				message = "#arguments.label# failed with exit code #arguments.result.exitCode#.",
				detail  = arguments.result.output
			);
		}
	}

	/** Returns a Markdown level-two heading for a changelog version. */
	string function versionHeading( required string version ){
		return repeatString( chr( 35 ), 2 ) & " [#arguments.version#]";
	}
}
