/**
 * Runs the project tests for `box release test` and for the package build.
 *
 * If release.json lists engines, `release test` uses EngineRunner to test each one. If no
 * engines are listed, it runs the tests once against the test server. That server must be
 * running.
 */
component extends="commandbox-release.models.BaseService" {

	/**
	 * Runs the tests on every configured engine, or once against the running test server.
	 */
	function run(){
		if ( arrayLen( variables.settings.engines ) ) {
			return service( "EngineRunner" ).run();
		}

		print
			.line( "No engines are listed in release.json. Running the tests once against the test server." )
			.line( "Add engines to release.json to run the tests on more than one CFML engine." )
			.line()
			.toConsole();
		runOnce();
		print.boldGreenLine( "The tests passed." ).toConsole();
	}

	/**
	 * Runs the suite once and stops when the server is down or the tests fail.
	 */
	function runOnce(){
		ensureReachable();
		print.blueLine( "Running the tests..." ).toConsole();
		if ( !suitePasses() ) {
			if ( len( lastRunError() ) ) {
				print.redLine( "The test runner did not finish: " & lastRunError() ).toConsole();
				return stop(
					"The test runner at #variables.settings.testRunner# did not return results. "
					& "Check the server and the runner, or use --skipTests to build without running them."
				);
			}
			printFailures( lastFailures() );
			return stop( "The tests failed. Fix them, or use --skipTests to build without running them." );
		}
	}

	/**
	 * Runs the tests and returns true if they all pass. It returns false after a failure instead
	 * of throwing, so EngineRunner can test the next engine. lastFailures() then names the tests
	 * that failed. If the runner errored before it returned results, such as a 500 or a timeout,
	 * lastRunError() has its message instead.
	 *
	 * It asks the runner to stop after the first spec bundle that fails. The stock TestBox
	 * runner.cfm ignores this flag and runs every bundle. See the README to make a runner use it.
	 */
	boolean function suitePasses(){
		variables.failures = [];
		variables.runError = "";
		var resultFile     = getTempFile( getTempDirectory(), "release-tests" );
		var passed         = false;
		try {
			command( "testbox run" )
				.params(
					runner     = variables.settings.testRunner,
					verbose    = false,
					outputFile = resultFile,
					options    = { "eagerFailure" : true }
				)
				.run();
			passed = variables.shell.getExitCode() == 0;
		} catch ( any e ) {
			passed             = false;
			variables.runError = describeRunError( e );
		}
		if ( !passed ) {
			variables.failures = readFailures( resultFile );
		}
		try {
			fileDelete( resultFile );
		} catch ( any ignoredException ) {
			// The temp directory is cleaned up later.
		}
		return passed;
	}

	/**
	 * Returns the failed tests from the last suitePasses() call. Each item has bundle, suite,
	 * spec, status, and message. It is empty when the tests passed or the results could not be
	 * read. They are kept in variables.failures because variables.lastFailures is this function.
	 */
	array function lastFailures(){
		return variables.failures ?: [];
	}

	/**
	 * Returns why the runner did not return results in the last suitePasses() call. It is empty
	 * when the runner returned results, even if some tests failed.
	 */
	string function lastRunError(){
		return variables.runError ?: "";
	}

	/**
	 * Returns one readable line for an error from `testbox run`: the first lines of the message
	 * and detail, cut to 300 characters.
	 *
	 * @error The caught exception.
	 */
	private string function describeRunError( required any error ){
		var lines = [];
		for ( var text in [ arguments.error.message ?: "", arguments.error.detail ?: "" ] ) {
			for ( var line in listToArray( text, chr( 10 ) & chr( 13 ) ) ) {
				if ( len( trim( line ) ) && arrayLen( lines ) < 4 ) {
					lines.append( trim( line ) );
				}
			}
		}
		// The runner's response body can be a whole HTML error page, so keep the line short.
		var text = lines.toList( " " );
		if ( len( text ) > 300 ) {
			text = left( text, 300 ) & "...";
		}
		return len( text ) ? text : "unknown error";
	}

	/**
	 * Returns every failed or errored spec in a TestBox JSON result. A bundle that could not run
	 * at all is returned with an empty suite and spec.
	 *
	 * @results The decoded JSON result from the TestBox runner.
	 */
	array function failedSpecs( required struct results ){
		var failures = [];
		for ( var bundle in arguments.results.bundleStats ?: [] ) {
			var bundleName = bundle.path ?: bundle.name ?: "";
			var exception  = bundle.globalException ?: "";
			if ( isStruct( exception ) && !structIsEmpty( exception ) ) {
				failures.append( {
					"bundle"  : bundleName,
					"suite"   : "",
					"spec"    : "",
					"status"  : "Error",
					"message" : exception.message ?: ""
				} );
			}
			for ( var suite in bundle.suiteStats ?: [] ) {
				collectSuiteFailures( failures, bundleName, suite, "" );
			}
		}
		return failures;
	}

	/**
	 * Prints one line for each failed test, up to a limit.
	 *
	 * @failures The failures from failedSpecs().
	 * @indent   Text to print before each line.
	 */
	function printFailures( required array failures, string indent = "" ){
		var limit = 10;
		for ( var i = 1; i <= min( limit, arrayLen( arguments.failures ) ); i++ ) {
			print.redLine( arguments.indent & "Failed: " & describeFailure( arguments.failures[ i ] ) ).toConsole();
		}
		if ( arrayLen( arguments.failures ) > limit ) {
			print.redLine( arguments.indent & "...and #arrayLen( arguments.failures ) - limit# more." ).toConsole();
		}
	}

	/**
	 * Returns one readable line for a failure: bundle > suite > spec -- message.
	 *
	 * @failure One item from failedSpecs().
	 */
	private string function describeFailure( required struct failure ){
		var parts = [ arguments.failure.bundle ];
		for ( var part in [ arguments.failure.suite, arguments.failure.spec ] ) {
			if ( len( part ) ) {
				parts.append( part );
			}
		}
		var message = trim( listFirst( arguments.failure.message, chr( 10 ) & chr( 13 ) ) );
		return parts.toList( " > " ) & ( len( message ) ? " -- " & message : "" );
	}

	private function collectSuiteFailures(
		required array failures,
		required string bundleName,
		required struct suite,
		required string parentPath
	){
		var suitePath = listAppend( arguments.parentPath, arguments.suite.name ?: "", chr( 31 ) );
		for ( var spec in arguments.suite.specStats ?: [] ) {
			var status = spec.status ?: "";
			if ( status == "Failed" || status == "Error" ) {
				var message = spec.failMessage ?: "";
				if ( !len( message ) && isStruct( spec.error ?: "" ) ) {
					message = spec.error.message ?: "";
				}
				arguments.failures.append( {
					"bundle"  : arguments.bundleName,
					"suite"   : listChangeDelims( suitePath, " > ", chr( 31 ) ),
					"spec"    : spec.name ?: "",
					"status"  : status,
					"message" : message
				} );
			}
		}
		for ( var child in arguments.suite.suiteStats ?: [] ) {
			collectSuiteFailures( arguments.failures, arguments.bundleName, child, suitePath );
		}
	}

	/** Reads the failures from a result file. Returns an empty array when it cannot read them. */
	private array function readFailures( required string resultFile ){
		try {
			var content = fileRead( arguments.resultFile );
			return isJSON( content ) ? failedSpecs( deserializeJSON( content ) ) : [];
		} catch ( any ignoredException ) {
			return [];
		}
	}

	/**
	 * Stops if the test server does not answer. Report the server problem before running tests
	 * so the user does not mistake it for a test failure.
	 */
	function ensureReachable(){
		var probeUrl   = variables.config.probeUrl();
		var statusCode = probe( probeUrl, 15 );
		// Any status from 200 through 399 means that the site answered.
		if ( statusCode < 200 || statusCode >= 400 ) {
			return stop(
				"The test server at #probeUrl# did not answer (status #statusCode#). "
				& "Start the server, and then run this command again. "
				& "Use --skipTests to build without running tests."
			);
		}
	}
}
