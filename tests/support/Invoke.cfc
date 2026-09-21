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
		loadModule( repositoryRoot );

		command( arguments.line ).run();
	}
}
