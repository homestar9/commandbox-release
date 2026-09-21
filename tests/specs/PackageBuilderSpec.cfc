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
	}

	private any function builder(){
		return model( "PackageBuilder" ).forProject( model( "ProjectConfig" ).load( fixtureRoot ) );
	}
}
