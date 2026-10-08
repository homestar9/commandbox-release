/** Uses MockBox to check the engine process without starting real servers. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Engine test process", function(){
			it( "runs all configured engines before reporting results", function(){
				var runner = prepareMock( model( "EngineRunner" ) );
				runner.$property(
					propertyName  = "settings",
					propertyScope = "variables",
					mock          = {
						engines : [
							{ name : "First", configFile : "server-first.json" },
							{ name : "Second", configFile : "server-second.json" }
						]
					}
				);
				runner.$( "stopAllEngines" );
				runner.$( "runEngine" ).$results(
					{ name : "First", passed : false, minutes : "0.1", reason : "failed" },
					{ name : "Second", passed : true, minutes : "0.1", reason : "" }
				);
				runner.$( "report" );

				runner.run();
				expect( runner.$count( "runEngine" ) ).toBe( 2 );
				expect( runner.$count( "report" ) ).toBe( 1 );
			} );

			it( "stops an engine after its tests fail", function(){
				var runner  = prepareMock( model( "EngineRunner" ) );
				var printer = createPrinterStub();
				runner.$property( propertyName = "print", propertyScope = "variables", mock = printer );
				runner.$( "startEngine", { ok : true, reason : "" } );
				runner.$( "warmUp", { ok : true, reason : "" } );
				var failures = [ { bundle : "specs.A", suite : "A", spec : "works", status : "Failed", message : "no" } ];
				runner.$( "runTestSuite", { failed : true, failures : failures, runError : "" } );
				runner.$( "stopEngine" );
				runner.$( "recordFailure", { name : "Lucee", passed : false, minutes : "0.1", reason : "the tests failed" } );
				makePublic( runner, "runEngine" );

				var result = runner.runEngine( { name : "Lucee", configFile : "server-lucee.json" } );
				expect( result.passed ).toBeFalse();
				expect( runner.$count( "stopEngine" ) ).toBe( 1 );
				expect( runner.$count( "recordFailure" ) ).toBe( 1 );
				expect( runner.$callLog().recordFailure[ 1 ][ 4 ] ).toBe( failures );
			} );

			it( "reports a runner error instead of failed tests", function(){
				var runner  = prepareMock( model( "EngineRunner" ) );
				var printer = createPrinterStub();
				runner.$property( propertyName = "print", propertyScope = "variables", mock = printer );
				runner.$( "startEngine", { ok : true, reason : "" } );
				runner.$( "warmUp", { ok : true, reason : "" } );
				runner.$( "runTestSuite", { failed : true, failures : [], runError : "Error executing tests: 500" } );
				runner.$( "stopEngine" );
				runner.$( "recordFailure", { name : "Lucee", passed : false, minutes : "0.1", reason : "" } );
				makePublic( runner, "runEngine" );

				runner.runEngine( { name : "Lucee", configFile : "server-lucee.json" } );
				expect( runner.$count( "stopEngine" ) ).toBe( 1 );
				expect( runner.$callLog().recordFailure[ 1 ][ 3 ] ).toBe( "the test runner did not finish: Error executing tests: 500" );
			} );

			it( "lists the failed tests under a failed engine in the report", function(){
				var runner  = prepareMock( model( "EngineRunner" ) );
				var lines   = [];
				var printer = createRecordingPrinter( lines );
				runner.$property( propertyName = "print", propertyScope = "variables", mock = printer );
				var testRunner = model( "TestRunner" ).usePrinter( printer );
				runner.$( "service", testRunner );
				runner.$( "stop" );
				makePublic( runner, "report" );

				runner.report(
					[
						{
							name     : "Lucee",
							passed   : false,
							minutes  : "0.1",
							reason   : "the tests failed",
							failures : [ { bundle : "specs.A", suite : "A suite", spec : "works", status : "Failed", message : "Expected 1" } ]
						}
					],
					getTickCount()
				);

				expect( lines.toList( chr( 10 ) ) ).toInclude( "Failed: specs.A > A suite > works -- Expected 1" );
				expect( runner.$count( "stop" ) ).toBe( 1 );
			} );
		} );
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	private any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "boldLine", "redLine", "greenLine", "boldGreenLine", "boldRedLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}

	private any function createPrinterStub(){
		var printer = createStub();
		printer.$( "line", printer );
		printer.$( "boldBlueLine", printer );
		printer.$( "toConsole", printer );
		return printer;
	}
}
