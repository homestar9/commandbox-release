/** Checks how TestRunner reads failed tests from a TestBox JSON result. */
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
		} );
	}

	private struct function suite( required string name, array specs = [], array children = [] ){
		return { name : arguments.name, specStats : arguments.specs, suiteStats : arguments.children };
	}

	private struct function spec( required string name, required string status, string message = "" ){
		return { name : arguments.name, status : arguments.status, failMessage : arguments.message };
	}
}
