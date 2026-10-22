/** Checks how PackageBuilder combines ignore patterns. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "PackageBuilder ignore patterns", function(){
			beforeEach( function(){
				fixtureRoot = createTempProject();
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			it( "combines the module's own patterns with the box.json ignore list", function(){
				writeJSON( fixtureRoot & "/box.json", { name : "Sample", version : "1.0.0", ignore : [ "/tests/", " /docs/ ", "" ] } );
				writeJSON( fixtureRoot & "/release.json", { stagingDir : "build-staging", artifactsDir : "out" } );

				var patterns = builder().ignorePatterns();
				for ( var expected in [ ".git/", ".gitignore", ".npmignore", "/release.json", "/build-staging/", "/out/", "/tests/", "/docs/" ] ) {
					expect( patterns ).toInclude( expected );
				}
				expect( patterns ).notToInclude( "" );
			} );

			it( "works without an ignore list in box.json", function(){
				writeJSON( fixtureRoot & "/box.json", { name : "Sample", version : "1.0.0" } );
				writeJSON( fixtureRoot & "/release.json", {} );

				var patterns = arrayToList( builder().ignorePatterns() );
				expect( patterns ).toInclude( "/.tmp/" );
				expect( patterns ).toInclude( "/.artifacts/" );
				expect( patterns ).toInclude( ".gitignore" );
			} );
		} );

		describe( "PackageBuilder tests step", function(){
			beforeEach( function(){
				fixtureRoot = createTempProject();
				writeJSON( fixtureRoot & "/box.json", { name : "Sample", slug : "sample", version : "1.0.0" } );
				writeJSON( fixtureRoot & "/release.json", {} );
				lines         = [];
				packageBuilder = prepareMock( builder() );
				packageBuilder.$( "prepare" );
				packageBuilder.$( "fillDefaults" );
				packageBuilder.$( "buildSource" );
				packageBuilder.$( "buildChecksums" );
				packageBuilder.$( "service" );
				packageBuilder.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( lines ) );
				var fileSystemUtil = createStub();
				fileSystemUtil.$( "createMapping" );
				packageBuilder.$property( propertyName = "fileSystemUtil", propertyScope = "variables", mock = fileSystemUtil );
				packageBuilder.$property( propertyName = "exportsDir", propertyScope = "variables", mock = fixtureRoot & "/exports" );
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			it( "says which branch passed the tests instead of warning", function(){
				packageBuilder.run( projectName = "sample", version = "1.1.0", testedOn = "release/1.1.0" );

				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "The tests passed on release/1.1.0" );
				expect( output ).notToInclude( "WARNING" );
				expect( packageBuilder.$count( "service" ) ).toBe( 0 );
			} );

			it( "still warns when skipTests is set", function(){
				packageBuilder.run( projectName = "sample", version = "1.1.0", skipTests = true );

				expect( lines.toList( chr( 10 ) ) ).toInclude( "WARNING: This build skipped the tests (requested with skipTests)." );
			} );
		} );
	}

	private any function builder(){
		return model( "PackageBuilder" ).forProject( model( "ProjectConfig" ).load( fixtureRoot ) );
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	private any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "greenLine", "yellowLine", "boldYellowLine", "boldMagentaLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}
}
