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
				runner.$( "runTestSuite", true );
				runner.$( "stopEngine" );
				runner.$( "recordFailure", { name : "Lucee", passed : false, minutes : "0.1", reason : "the tests failed" } );
				makePublic( runner, "runEngine" );

				var result = runner.runEngine( { name : "Lucee", configFile : "server-lucee.json" } );
				expect( result.passed ).toBeFalse();
				expect( runner.$count( "stopEngine" ) ).toBe( 1 );
				expect( runner.$count( "recordFailure" ) ).toBe( 1 );
			} );
		} );
	}

	private any function createPrinterStub(){
		var printer = createStub();
		printer.$( "line", printer );
		printer.$( "boldBlueLine", printer );
		printer.$( "toConsole", printer );
		return printer;
	}
}
