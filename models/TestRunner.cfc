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
			return stop( "The tests failed. Fix them, or use --skipTests to build without running them." );
		}
	}

	/**
	 * Runs the tests and returns true if they all pass. It returns false after a failure instead
	 * of throwing, so EngineRunner can test the next engine.
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
