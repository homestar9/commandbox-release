/**
 * Checks how TestRunner reads failed tests from a TestBox JSON result, and how it runs a test
 * command. A stub replaces ProcessRunner, so no box process starts.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Failed test report", function(){
			beforeEach( function(){
				testRunner = prepareMock( model( "TestRunner" ) );
			} );

			it( "returns nothing when every test passed", function(){
				var results = {
					bundleStats : [
						{
							path            : "tests.specs.PassSpec",
							globalException : "",
							suiteStats      : [ suite( "Pass suite", [ spec( "works", "Passed" ) ] ) ]
						}
					]
				};
				expect( testRunner.failedSpecs( results ) ).toBeEmpty();
			} );

			it( "finds failed and errored specs in nested suites", function(){
				var inner   = suite( "inner", [ spec( "breaks", "Error", "Variable [X] does not exist" ) ] );
				var outer   = suite( "outer", [ spec( "fails", "Failed", "Expected [2] but received [1]" ), spec( "passes", "Passed" ) ], [ inner ] );
				var results = { bundleStats : [ { path : "tests.specs.MixedSpec", globalException : "", suiteStats : [ outer ] } ] };

				var failures = testRunner.failedSpecs( results );
				expect( failures ).toHaveLength( 2 );
				expect( failures[ 1 ] ).toBe( {
					bundle  : "tests.specs.MixedSpec",
					suite   : "outer",
					spec    : "fails",
					status  : "Failed",
					message : "Expected [2] but received [1]"
				} );
				expect( failures[ 2 ].suite ).toBe( "outer > inner" );
				expect( failures[ 2 ].status ).toBe( "Error" );
				expect( failures[ 2 ].message ).toBe( "Variable [X] does not exist" );
			} );

			it( "uses the error message when a spec has no failure message", function(){
				var errored = spec( "breaks", "Error" );
				errored.error = { message : "Division by zero" };
				var results = { bundleStats : [ { path : "tests.specs.ErrorSpec", globalException : "", suiteStats : [ suite( "S", [ errored ] ) ] } ] };

				expect( testRunner.failedSpecs( results )[ 1 ].message ).toBe( "Division by zero" );
			} );

			it( "reports a bundle that could not run", function(){
				var results = {
					bundleStats : [
						{ path : "tests.specs.BrokenSpec", globalException : { message : "Invalid syntax" }, suiteStats : [] }
					]
				};

				var failures = testRunner.failedSpecs( results );
				expect( failures ).toHaveLength( 1 );
				expect( failures[ 1 ].bundle ).toBe( "tests.specs.BrokenSpec" );
				expect( failures[ 1 ].spec ).toBe( "" );
				expect( failures[ 1 ].message ).toBe( "Invalid syntax" );
			} );

			it( "describes a failure on one line", function(){
				makePublic( testRunner, "describeFailure" );
				var line = testRunner.describeFailure( {
					bundle  : "tests.specs.A",
					suite   : "outer > inner",
					spec    : "works",
					status  : "Failed",
					message : "First line" & chr( 10 ) & "Second line"
				} );
				expect( line ).toBe( "tests.specs.A > outer > inner > works -- First line" );

				var bundleOnly = testRunner.describeFailure( { bundle : "tests.specs.B", suite : "", spec : "", status : "Error", message : "" } );
				expect( bundleOnly ).toBe( "tests.specs.B" );
			} );

			it( "returns no failures before the tests run", function(){
				expect( testRunner.lastFailures() ).toBeEmpty();
			} );

			it( "has no run error before the tests run", function(){
				expect( testRunner.lastRunError() ).toBe( "" );
			} );

			it( "keeps the error when the runner does not return results", function(){
				var testboxRun = createStub();
				testboxRun.$( "params", testboxRun );
				testboxRun
					.$( "run" )
					.$throws(
						type    = "commandException",
						message = "Error executing tests:",
						detail  = "Connection Failure" & chr( 10 ) & "Status code: 500"
					);
				testRunner.$( "command", testboxRun );
				useTestServer( "http://localhost/tests/runner.cfm" );

				expect( testRunner.suitePasses() ).toBeFalse();
				expect( testRunner.lastRunError() ).toBe( "Error executing tests: Connection Failure Status code: 500" );
				expect( testRunner.lastFailures() ).toBeEmpty();
			} );

			it( "gives testbox run the full URL of the engine's runner", function(){
				var testboxRun = createStub();
				testboxRun.$( "params", testboxRun );
				testboxRun.$( "run" ).$throws( type = "commandException", message = "Stop here." );
				testRunner.$( "command", testboxRun );
				var testServer = useTestServer( "http://127.0.0.1:60401/tests/runner.cfm" );

				testRunner.suitePasses( "server-lucee@5.json" );
				expect( testServer.$callLog().runnerUrl[ 1 ][ 1 ] ).toBe( "server-lucee@5.json" );
				expect( testboxRun.$callLog().params[ 1 ].runner ).toBe( "http://127.0.0.1:60401/tests/runner.cfm" );
			} );

			it( "keeps the error when the runner URL cannot be found", function(){
				testRunner.$( "command" ).$throws( type = "Spec.Unexpected", message = "testbox run must not start." );
				var testServer = useTestServer( "" );
				testServer
					.$( "runnerUrl" )
					.$throws( type = "Release.Stop", message = "testRunner is the path /tests/runner.cfm, but no server has started for this project." );

				expect( testRunner.suitePasses() ).toBeFalse();
				expect( testRunner.lastRunError() ).toInclude( "no server has started" );
			} );

			it( "describes a runner error with no message", function(){
				makePublic( testRunner, "describeRunError" );
				expect( testRunner.describeRunError( { message : "", detail : "" } ) ).toBe( "unknown error" );
			} );
		} );

		describe( "Test command", function(){
			beforeEach( function(){
				lines         = [];
				processRunner = createStub();
				testRunner    = prepareMock( model( "TestRunner" ) );
				testRunner.usePrinter( createRecordingPrinter( lines ) );
				testRunner.$property( propertyName = "processRunner", propertyScope = "variables", mock = processRunner );
				testRunner.$property( propertyName = "root", propertyScope = "variables", mock = "D:/projects/sample" );
				testRunner.$property(
					propertyName  = "settings",
					propertyScope = "variables",
					mock          = { testCommand : "run-script test", testRunner : "http://127.0.0.1:1/tests/runner.cfm", engines : [] }
				);
				// The test command needs no server, so a server check would be a bug.
				testRunner.$( "ensureReachable" ).$throws( type = "Release.Stop", message = "The test server did not answer." );
				testRunner.$( "suitePasses", false );
			} );

			it( "runs the command with box in the project root and shows its output", function(){
				processRunner.$( method = "run", callback = function(){
					arguments.onLine( "Fixture tests passed." );
					return { exitCode : 0, output : "Fixture tests passed." };
				} );

				testRunner.runOnce();
				var call = processRunner.$callLog().run[ 1 ];
				expect( call.name ).toBe( "box" );
				expect( call.args ).toBe( [ "run-script test" ] );
				expect( call.workingDirectory ).toBe( "D:/projects/sample" );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "Running the tests with: box run-script test" );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "Fixture tests passed." );
				expect( testRunner.$count( "ensureReachable" ) ).toBe( 0 );
				expect( testRunner.$count( "suitePasses" ) ).toBe( 0 );
			} );

			it( "stops with the command and its exit code when it fails", function(){
				processRunner.$( "run", { exitCode : 1, output : "1 test failed." } );
				processRunner.$( "commandExists", true );

				expect( function(){
					testRunner.runOnce();
				} ).toThrow( type = "Release.Stop", regex = "The test command failed: box run-script test \(exit code 1\)" );
			} );

			it( "explains when box cannot be found", function(){
				processRunner.$( "run", { exitCode : 127, output : "Could not start 'box'" } );
				processRunner.$( "commandExists", false );

				expect( function(){
					testRunner.runOnce();
				} ).toThrow( type = "Release.Stop", regex = "box was not found" );
			} );

			it( "runs the command for release test instead of the engines", function(){
				processRunner.$( "run", { exitCode : 0, output : "" } );
				testRunner.$( "service" ).$throws( type = "Spec.Unexpected", message = "EngineRunner must not run." );
				// ProjectConfig refuses this mix. TestRunner still prefers the command.
				testRunner.$property(
					propertyName  = "settings",
					propertyScope = "variables",
					mock          = { testCommand : "run-script test", engines : [ { name : "Lucee 5", configFile : "server-lucee@5.json" } ] }
				);

				testRunner.run();
				expect( processRunner.$count( "run" ) ).toBe( 1 );
				expect( testRunner.$count( "service" ) ).toBe( 0 );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "The tests passed." );
			} );
		} );
	}

	/**
	 * Makes testRunner use a TestServer stub that returns the given runner URL, and returns the
	 * stub.
	 */
	private any function useTestServer( required string runnerUrl ){
		var testServer = createStub();
		testServer.$( "runnerUrl", arguments.runnerUrl );
		testRunner.$( "service", testServer );
		testRunner.$property(
			propertyName  = "settings",
			propertyScope = "variables",
			mock          = { testRunner : "/tests/runner.cfm" }
		);
		return testServer;
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	private any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "blueLine", "redLine", "greenLine", "boldGreenLine", "boldRedLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}

	private struct function suite( required string name, array specs = [], array children = [] ){
		return { name : arguments.name, specStats : arguments.specs, suiteStats : arguments.children };
	}

	private struct function spec( required string name, required string status, string message = "" ){
		return { name : arguments.name, status : arguments.status, failMessage : arguments.message };
	}
}
