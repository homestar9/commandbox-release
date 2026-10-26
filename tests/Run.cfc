/**
 * Runs the commandbox-release TestBox tests in CommandBox.
 *
 * Run `box run-script test` from the repository root. The tests do not need a web server. This
 * runner loads this working copy as the commandbox-release module. It runs all tests and
 * prints the results. It returns an error if a test fails.
 *
 * `box run-script test:fast` skips the integration bundles. They start box processes and take
 * most of the time. Run the full suite before a commit.
 */
component {

	/** The bundles that run real commands in temporary projects. */
	variables.integrationBundles = [ "CommandIntegrationSpec", "GitflowSpec", "ReleaseFlowSpec" ];

	/**
	 * @bundles One or more bundle paths, such as tests.specs.VersionServiceSpec. The default
	 *          runs every bundle in tests/specs.
	 * @fast    Skips the integration bundles.
	 */
	function run( string bundles = "", boolean fast = false ){
		var repositoryRoot = reReplace(
			reReplace( getDirectoryFromPath( getCurrentTemplatePath() ), "[\\/]$", "" ),
			"[\\/][^\\/]+$",
			""
		);

		loadWorkingCopy( repositoryRoot );
		prepareTestWork( repositoryRoot );
		fileSystemUtil.createMapping( "tests", repositoryRoot & "/tests" );
		fileSystemUtil.createMapping( "testbox", repositoryRoot & "/testbox" );

		var runnerArguments = { options : { coverage : { enabled : false } } };
		if ( len( trim( arguments.bundles ) ) ) {
			runnerArguments.bundles = arguments.bundles;
		} else {
			runnerArguments.directory = { mapping : "tests.specs", recurse : true };
			if ( arguments.fast ) {
				runnerArguments.directory.filter = function( path ){
					return !isIntegrationBundle( arguments.path );
				};
				print.line( "Fast run: skipping the integration bundles (#arrayToList( variables.integrationBundles, ", " )#)." ).toConsole();
			}
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

	/** Returns true for a spec file path that belongs to an integration bundle. */
	private boolean function isIntegrationBundle( required string path ){
		var name = listFirst( listLast( replace( arguments.path, "\", "/", "all" ), "/" ), "." );
		return arrayFindNoCase( variables.integrationBundles, name ) > 0;
	}

	/**
	 * Creates .test-work and marks it ignored for Dropbox. The repository can live in a Dropbox
	 * folder. Without the mark, Dropbox syncs every temporary project and can lock files while a
	 * test deletes them. Windows keeps the mark in an alternate data stream. Mac and Linux keep
	 * it in an extended attribute. A failure only means that the folder is synced.
	 */
	private void function prepareTestWork( required string repositoryRoot ){
		var workDir = arguments.repositoryRoot & "/.test-work";
		if ( !directoryExists( workDir ) ) {
			directoryCreate( workDir, true, true );
		}
		try {
			if ( markDropboxIgnored( workDir ) ) {
				print.line( "Marked .test-work as ignored for Dropbox." ).toConsole();
			}
		} catch ( any ignoredException ) {
			// The folder stays synced. The tests still work.
		}
	}

	/** Sets the Dropbox ignore mark. Returns true when it set the mark and false when it was there. */
	private boolean function markDropboxIgnored( required string workDir ){
		if ( findNoCase( "Windows", server.os.name ) ) {
			var streamPath = replace( arguments.workDir, "/", "\", "all" ) & ":com.dropbox.ignored";
			try {
				createObject( "java", "java.io.FileInputStream" ).init( streamPath ).close();
				return false;
			} catch ( any missingStream ) {
				// The mark is not set yet.
			}
			var stream = createObject( "java", "java.io.FileOutputStream" ).init( streamPath );
			stream.write( charsetDecode( "1", "utf-8" ) );
			stream.close();
			return true;
		}

		var runner = wirebox.getInstance( "ProcessRunner@commandbox-release" );
		if ( !runner.commandExists( "xattr" ) ) {
			return false;
		}
		if ( runner.run( "xattr", [ "-p", "com.dropbox.ignored", arguments.workDir ], arguments.workDir ).exitCode == 0 ) {
			return false;
		}
		return runner.run( "xattr", [ "-w", "com.dropbox.ignored", "1", arguments.workDir ], arguments.workDir ).exitCode == 0;
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

		forgetModuleMetadata( arguments.repositoryRoot );
		loadModule( arguments.repositoryRoot );
	}

	/**
	 * Removes this module's entries from the CommandBox metadata cache. CommandBox keeps WireBox
	 * component metadata, such as injected properties, in files on disk. It does not notice
	 * edits to the working copy, so a model would keep the injections it had when the cache was
	 * written. The cache names each file after its key, so this removes the keys for every model
	 * and command file. tests/support/Invoke.cfc has the same function.
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
