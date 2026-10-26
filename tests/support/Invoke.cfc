/**
 * Runs one release command with this checkout loaded as the module.
 *
 * Run it by hand in a project folder to try the working copy without installing it:
 *
 *   box task run taskFile=<repo>/tests/support/Invoke.cfc :line="release check"
 *
 * The task runs the real command from the working copy. If the command fails, the task returns
 * an error, so box exits with a nonzero code.
 *
 * The integration specs use a second mode. tests/support/FixtureProcess.cfc keeps one box open
 * per test bundle and sends it this task once per command, with root, nonce, and reload=false.
 * The task runs the command in root and prints its output between two marker lines that carry
 * the nonce. The end marker also carries the exit code. The task then clears the exit code and
 * returns, so the shell can take the next command.
 *
 * CommandBox expands ${...} and backtick expressions in each line it reads, so a command line
 * must not contain them.
 */
component {

	/**
	 * @line   The command line to run, such as "release bump patch --dryRun". Leave it empty to
	 *         load the module and run nothing. The argument is named line because command() is
	 *         the function that runs it.
	 * @root   The folder to run the command in. The default is the current folder.
	 * @nonce  Marks the output for the shared mode. Leave it empty when running by hand.
	 * @reload Unloads an installed commandbox-release and loads this working copy. Set it to
	 *         false when the same shell loaded the working copy already.
	 */
	function run( string line = "", string root = "", string nonce = "", boolean reload = true ){
		var supportDir     = reReplace( getDirectoryFromPath( getCurrentTemplatePath() ), "[\\/]$", "" );
		var repositoryRoot = reReplace( reReplace( supportDir, "[\\/][^\\/]+$", "" ), "[\\/][^\\/]+$", "" );
		var shared         = len( trim( arguments.nonce ) ) > 0;

		if ( arguments.reload ) {
			loadWorkingCopy( repositoryRoot );
		}
		if ( !len( trim( arguments.line ) ) ) {
			if ( shared ) {
				print.line( "__INVOKE_END__ #arguments.nonce# exitCode=0" ).toConsole();
			}
			return;
		}

		var startDir = shell.pwd();
		var exitCode = 0;
		if ( shared ) {
			print.line( "__INVOKE_BEGIN__ #arguments.nonce#" ).toConsole();
		}
		try {
			var runner = command( arguments.line );
			if ( len( trim( arguments.root ) ) ) {
				runner.inWorkingDirectory( reReplace( arguments.root, "[\\/]$", "" ) & "/" );
			}
			runner.run();
		} catch ( "commandException" exception ) {
			exitCode = failureCode( exception );
			if ( !shared ) {
				rethrow;
			}
			printFailure( exception );
		} catch ( any exception ) {
			exitCode = 1;
			if ( !shared ) {
				rethrow;
			}
			printFailure( exception );
		} finally {
			try {
				shell.cd( startDir );
			} catch ( any ignoredException ) {
				// The next request sets its own folder.
			}
		}

		if ( shared ) {
			print.line( "__INVOKE_END__ #arguments.nonce# exitCode=#exitCode#" ).toConsole();
			shell.setExitCode( 0 );
		}
	}

	/**
	 * Prints a failed command's message and detail. The shell prints them when the task fails,
	 * but the shared mode keeps the shell running, so the task prints them itself.
	 */
	private void function printFailure( required any exception ){
		print.boldRedLine( "ERROR: " & arguments.exception.message ).toConsole();
		if ( len( arguments.exception.detail ?: "" ) ) {
			print.redLine( arguments.exception.detail ).toConsole();
		}
	}

	/** Returns the exit code of a failed command. A failure without a code counts as 1. */
	private numeric function failureCode( required any exception ){
		var code = val( arguments.exception.errorCode ?: "" );
		if ( code == 0 ) {
			code = val( shell.getExitCode() );
		}
		return code == 0 ? 1 : code;
	}

	/** Unloads a module with the same name or folder name, then loads this working copy. */
	private void function loadWorkingCopy( required string repositoryRoot ){
		// CommandBox names a module after its folder, so unload a global module with either name.
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
