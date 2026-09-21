/**
 * Runs the project tests for `box release test` and for the package build.
 *
 * With engines listed in release.json, `release test` hands the work to EngineRunner, which
 * starts each engine in turn. Without engines, it runs the suite once against the test runner
 * URL, which must already be answering.
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
			return stop( "The tests failed. Fix them, or use --skipTests to build without running them." );
		}
	}

	/**
	 * Runs the suite and returns true when every test passed. It never throws, so a caller such
	 * as EngineRunner can continue with the next engine after a failure.
	 */
	boolean function suitePasses(){
		try {
			command( "testbox run" )
				.params( runner = variables.settings.testRunner, verbose = false )
				.run();
			return variables.shell.getExitCode() == 0;
		} catch ( any ignoredException ) {
			return false;
		}
	}

	/**
	 * Stops when the test server does not answer. This separate check reports a server problem
	 * instead of incorrectly reporting a test failure.
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
