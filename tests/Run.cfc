/**
 * Runs the commandbox-release TestBox tests in CommandBox.
 *
 * Run `box run-script test` from the repository root. The tests do not need a web server. This
 * runner loads this working copy as the commandbox-release module. It runs all tests and
 * prints the results. It returns an error if a test fails.
 */
component {

	function run( string bundles = "" ){
		var repositoryRoot = reReplace(
			reReplace( getDirectoryFromPath( getCurrentTemplatePath() ), "[\\/]$", "" ),
			"[\\/][^\\/]+$",
			""
		);

		loadWorkingCopy( repositoryRoot );
		fileSystemUtil.createMapping( "tests", repositoryRoot & "/tests" );
		fileSystemUtil.createMapping( "testbox", repositoryRoot & "/testbox" );

		var runnerArguments = { options : { coverage : { enabled : false } } };
		if ( len( trim( arguments.bundles ) ) ) {
			runnerArguments.bundles = arguments.bundles;
		} else {
			runnerArguments.directory = { mapping : "tests.specs", recurse : true };
		}
		var testRunner = new testbox.system.TestBox( argumentCollection = runnerArguments );
		var results = testRunner.runRaw();
		var reporter = new testbox.system.reports.TextReporter();
		var report   = reporter.runReport(
			results    = results,
			testbox    = testRunner,
			justReturn = true
		);
		print.line( report ).toConsole();

		var problemCount = results.getTotalFail() + results.getTotalError();
		if ( problemCount ) {
			return error( "#problemCount# commandbox-release test#( problemCount == 1 ? "" : "s" )# failed." );
		}
	}

	/**
	 * Loads this working copy as commandbox-release. First unloads a module with the same name
	 * or the same folder name. CommandBox uses folder names for modules, and loadModule() does
	 * not replace a module that is already loaded.
	 */
	private void function loadWorkingCopy( required string repositoryRoot ){
		var moduleService = wirebox.getInstance( "moduleService" );
		for ( var moduleName in [ "commandbox-release", listLast( arguments.repositoryRoot, "/\" ) ] ) {
			if ( moduleService.isModuleRegistered( moduleName ) ) {
				moduleService.unloadAndUnregisterModule( moduleName );
			}
		}
		loadModule( arguments.repositoryRoot );
	}
}
