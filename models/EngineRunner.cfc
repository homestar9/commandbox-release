/**
 * Runs the project tests on each configured CFML engine.
 *
 * `box release test` reads engine names and server JSON filenames from release.json. The
 * engines run one at a time because they use the same port.
 *
 * It stops old servers before starting the first engine. For each engine, it starts the
 * server, waits for the site, runs the tests, and stops the server. A failure does not stop
 * the remaining engines. The final report returns an error when any engine fails.
 */
component extends="commandbox-release.models.BaseService" {

	/**
	 * Tests each engine and prints all results. It stops all servers before returning. It
	 * returns an error after the report when any engine fails.
	 */
	function run(){
		if ( !arrayLen( variables.settings.engines ) ) {
			return fail(
				"No engines are listed in release.json.",
				[
					'"engines": [',
					'    { "name": "Lucee 5",    "configFile": "server-lucee@5.json" },',
					'    { "name": "Adobe 2023", "configFile": "server-adobe@2023.json" }',
					']',
					"",
					"Each configFile must name a server JSON file in the project root.",
					"The command runs each engine in the listed order."
				],
				"Add engines to release.json like this"
			);
		}

		var results = [];
		var started = getTickCount();

		// Only one server can use the test port. Stop every configured server because the
		// command does not know which server is running.
		stopAllEngines();

		for ( var engine in variables.settings.engines ) {
			results.append( runEngine( engine ) );
		}

		return report( results, started );
	}

	// ENGINE WORKFLOW

	private struct function runEngine( required struct engine ){
		var engineName  = arguments.engine.name ?: arguments.engine.configFile;
		var engineStart = getTickCount();
		print.line().boldBlueLine( "=== #engineName# (#arguments.engine.configFile#) ===" ).toConsole();

		var startResult = startEngine( arguments.engine, engineName );
		if ( !startResult.ok ) {
			return recordFailure( engineName, engineStart, startResult.reason );
		}

		var warmUpResult = warmUp( arguments.engine, engineName );
		if ( !warmUpResult.ok ) {
			return recordFailure( engineName, engineStart, warmUpResult.reason );
		}

		var suiteResult = runTestSuite( engineName );
		stopEngine( arguments.engine.configFile );
		if ( suiteResult.failed && len( suiteResult.runError ) ) {
			return recordFailure( engineName, engineStart, "the test runner did not finish: " & suiteResult.runError );
		}
		if ( suiteResult.failed ) {
			return recordFailure( engineName, engineStart, "the tests failed", suiteResult.failures );
		}

		return recordSuccess( engineName, engineStart );
	}

	/**
	 * Runs the suite on the running engine. Returns { failed, failures, runError }, where
	 * failures names the tests that failed and runError says why the runner gave no results.
	 */
	private struct function runTestSuite( required string engineName ){
		print.blueLine( "Running the tests on #arguments.engineName#..." ).toConsole();
		var testRunner = service( "TestRunner" );
		var passed     = testRunner.suitePasses();
		return {
			"failed"   : !passed,
			"failures" : passed ? [] : testRunner.lastFailures(),
			"runError" : passed ? "" : testRunner.lastRunError()
		};
	}

	/**
	 * Starts one engine server and returns { ok, reason }. It returns the failure instead of
	 * stopping so the next engine can still run.
	 */
	private struct function startEngine( required struct engine, required string engineName ){
		// A server stop command can finish before the process releases its port. Wait for the
		// port so that the old process does not cause the next engine to fail.
		waitForPortToFree( arguments.engineName );

		var startFailed = false;
		var startError  = "";
		try {
			command( "server start" )
				.params( serverConfigFile = arguments.engine.configFile )
				.run();
			startFailed = ( variables.shell.getExitCode() != 0 );
		} catch ( any exception ) {
			startFailed = true;
			startError  = exception.message;
		}
		if ( startFailed ) {
			print
				.line()
				.boldLine( "Common reasons that a server does not start:" )
				.yellowLine( "  The server JSON file is missing from the project root." )
				.yellowLine( "  Another server is still using the port." )
				.yellowLine( "  CommandBox could not download the engine." )
				.line()
				.boldLine( "Run this command to see the full error:" )
				.yellowLine( "  box server start serverConfigFile=#arguments.engine.configFile#" )
				.line()
				.toConsole();
			// A failed start may still leave a process on the port. Stop it before starting
			// the next engine.
			stopEngine( arguments.engine.configFile );
			return {
				"ok"     : false,
				"reason" : "The server did not start" & ( len( startError ) ? ": " & startError : "" )
			};
		}

		return { "ok" : true, "reason" : "" };
	}

	/**
	 * Waits for the test port to become free. It stops waiting after one minute. The next start
	 * attempt will report the error when the port is still in use.
	 */
	private function waitForPortToFree( required string engineName ){
		var probeUrl = variables.config.probeUrl();
		for ( var attempt = 1; attempt <= 12; attempt++ ) {
			if ( probe( probeUrl, 5 ) == 0 ) {
				return;
			}
			if ( attempt == 1 ) {
				print.yellowLine( "Waiting for the previous server to release the port..." ).toConsole();
			}
			sleep( 5000 );
		}
		print
			.yellowLine( "The port is still in use. Trying to start #arguments.engineName# anyway." )
			.toConsole();
	}

	/**
	 * Waits for the site before running tests. Tests could fail for the wrong reason if the app
	 * is still starting. It returns { ok, reason } so another engine can run after a failure.
	 */
	private struct function warmUp( required struct engine, required string engineName ){
		var attempts     = variables.settings.warmup.attempts;
		var delaySeconds = variables.settings.warmup.delaySeconds;
		var probeUrl     = variables.config.probeUrl();

		print.blueLine( "Waiting for #arguments.engineName# (up to #attempts * delaySeconds# seconds)..." ).toConsole();
		var lastStatus = 0;
		for ( var attempt = 1; attempt <= attempts; attempt++ ) {
			lastStatus = probe( probeUrl, 60 );
			// Any status from 200 through 399 means that the site answered.
			if ( lastStatus >= 200 && lastStatus < 400 ) {
				print.greenLine( "#arguments.engineName# is up (status #lastStatus#)." ).toConsole();
				return { "ok" : true, "reason" : "" };
			}
			sleep( delaySeconds * 1000 );
		}

		stopEngine( arguments.engine.configFile );
		print
			.line()
			.yellowLine(
				"Repeated status 500 responses usually mean that the app cannot start on this engine. Run this command and read the server log:"
			)
			.yellowLine( "  box server start serverConfigFile=#arguments.engine.configFile#" )
			.line()
			.toConsole();

		return { "ok" : false, "reason" : "The server did not answer (last status: #lastStatus#)" };
	}

	/**
	 * Tries to stop every configured engine. Only one engine should be running. Errors do not
	 * stop this cleanup.
	 */
	private function stopAllEngines(){
		print.blueLine( "Stopping any running server..." ).toConsole();
		for ( var engine in variables.settings.engines ) {
			stopEngine( engine.configFile );
		}
	}

	/**
	 * Tries to stop one server without reporting an error. The next server start reports a port
	 * error if the old server did not stop.
	 */
	private function stopEngine( required string configFile ){
		try {
			command( "server stop" ).params( serverConfigFile = arguments.configFile ).run();
		} catch ( any ignoredException ) {
			// The server is already stopped or could not be stopped. Continue cleanup.
		}
	}

	private struct function recordFailure(
		required string engineName,
		required numeric engineStart,
		required string reason,
		array failures = []
	){
		var minutes = numberFormat( ( getTickCount() - arguments.engineStart ) / 60000, "0.9" );
		print.boldRedLine( "#arguments.engineName#: FAILED after #minutes# min -- #arguments.reason#" ).toConsole();
		return {
			"name"     : arguments.engineName,
			"passed"   : false,
			"minutes"  : minutes,
			"reason"   : arguments.reason,
			"failures" : arguments.failures
		};
	}

	private struct function recordSuccess( required string engineName, required numeric engineStart ){
		var minutes = numberFormat( ( getTickCount() - arguments.engineStart ) / 60000, "0.9" );
		print.boldGreenLine( "#arguments.engineName#: passed in #minutes# min." ).toConsole();
		return {
			"name"     : arguments.engineName,
			"passed"   : true,
			"minutes"  : minutes,
			"reason"   : "",
			"failures" : []
		};
	}

	/**
	 * Prints the result for each engine. It returns an error when one or more engines failed.
	 */
	private function report( required array results, required numeric started ){
		var totalMinutes  = numberFormat( ( getTickCount() - arguments.started ) / 60000, "0.9" );
		var failedResults = arguments.results.filter( function( result ){
			return !result.passed;
		} );

		print.line().boldLine( "Results (#totalMinutes# min total):" ).toConsole();
		for ( var result in arguments.results ) {
			if ( result.passed ) {
				print.greenLine( "  PASSED  #result.name# (#result.minutes# min)" ).toConsole();
			} else {
				print.redLine( "  FAILED  #result.name# (#result.minutes# min) -- #result.reason#" ).toConsole();
				service( "TestRunner" ).printFailures( result.failures ?: [], "          " );
			}
		}
		print.line().toConsole();

		if ( !failedResults.len() ) {
			print.boldGreenLine( "All #arguments.results.len()# engines passed." ).toConsole();
			return;
		}

		var failedNames = failedResults.map( function( result ){
			return result.name;
		} );

		return stop(
			"#failedResults.len()# of #arguments.results.len()# engines failed: "
			& failedNames.toList( ", " ) & "."
		);
	}
}
