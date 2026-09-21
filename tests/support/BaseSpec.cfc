/**
 * Provides shared setup for every test file. It gets module components from WireBox and
 * provides paths for the repository and temporary projects.
 *
 * tests/Run.cfc loads this checkout as commandbox-release before tests run. As a result,
 * "Name@commandbox-release" refers to the working copy.
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
	 * Deletes a temporary project. Dropbox and antivirus programs can briefly lock new files on
	 * Windows, so this function tries the delete more than once. A remaining folder is safe
	 * because every test uses a unique name under the ignored .test-work folder.
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
