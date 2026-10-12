/**
 * Runs one release command in the current folder with this checkout loaded as the module.
 *
 * Integration tests start a new `box` process in a temporary project and run this task:
 *
 *   box task run taskFile=<repo>/tests/support/Invoke.cfc :line="release check"
 *
 * This runs the real commands from the working copy. It does not install the module in the
 * developer's CommandBox. If a command fails, the task returns an error code that the test
 * can check.
 */
component {

	/**
	 * @line The command line to run, such as "release bump patch --dryRun". The argument is
	 *       named line because command() is the function that runs it.
	 */
	function run( required string line ){
		var supportDir     = reReplace( getDirectoryFromPath( getCurrentTemplatePath() ), "[\\/]$", "" );
		var repositoryRoot = reReplace( reReplace( supportDir, "[\\/][^\\/]+$", "" ), "[\\/][^\\/]+$", "" );

		// CommandBox names a module after its folder, so unload a global module with either name.
		var moduleService = wirebox.getInstance( "moduleService" );
		for ( var moduleName in [ "commandbox-release", listLast( repositoryRoot, "/\" ) ] ) {
			if ( moduleService.isModuleRegistered( moduleName ) ) {
				moduleService.unloadAndUnregisterModule( moduleName );
			}
		}

		forgetModuleMetadata( repositoryRoot );
		loadModule( repositoryRoot );

		command( arguments.line ).run();
	}

	/**
	 * Removes this module's entries from the CommandBox metadata cache. CommandBox keeps WireBox
	 * component metadata, such as injected properties, in files on disk. It does not notice
	 * edits to the working copy, so a model would keep the injections it had when the cache was
	 * written. The cache names each file after its key, so this removes the keys for every model
	 * and command file. Other entries stay, because the test runner process uses the same folder.
	 * tests/Run.cfc has the same function.
	 */
	private void function forgetModuleMetadata( required string repositoryRoot ){
		try {
			var metadataCache = wirebox.getCacheBox().getCache( "metadataCache" );
			var root          = replace( arguments.repositoryRoot, "\", "/", "all" );
			for ( var folder in [ "models", "commands" ] ) {
				for ( var file in directoryList( root & "/" & folder, true, "path", "*.cfc" ) ) {
					var relative = replace( replace( file, "\", "/", "all" ), root & "/" & folder & "/", "" );
					metadataCache.clear( "commandbox-release." & folder & "." & replace( left( relative, len( relative ) - 4 ), "/", ".", "all" ) );
				}
			}
		} catch ( any cacheFailure ) {
			// A locked cache file only means that stale metadata may be used.
		}
	}
}
