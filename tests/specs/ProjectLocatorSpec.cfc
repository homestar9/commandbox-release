/** Checks how a command finds its project root and settings file. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "ProjectLocator", function(){
			beforeEach( function(){
				fixtureRoot = createTempProject();
				locator     = model( "ProjectLocator" );
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			it( "finds the nearest box.json from a child folder", function(){
				fileWrite( fixtureRoot & "/box.json", "{}" );
				directoryCreate( fixtureRoot & "/models/deep", true, true );

				expect( locator.findRoot( fixtureRoot ) ).toBe( fixtureRoot );
				expect( locator.findRoot( fixtureRoot & "/models/deep" ) ).toBe( fixtureRoot );
				expect( locator.findRoot( replace( fixtureRoot, "/", "\", "all" ) & "\" ) ).toBe( fixtureRoot );
			} );

			it( "stops at a Git root without box.json", function(){
				directoryCreate( fixtureRoot & "/.git", true, true );
				directoryCreate( fixtureRoot & "/src", true, true );
				expect( function(){
					locator.findRoot( fixtureRoot & "/src" );
				} ).toThrow( type = "Release.NoProject" );
			} );

			it( "returns the release.json path or an empty string", function(){
				expect( locator.configFile( fixtureRoot ) ).toBe( "" );

				fileWrite( fixtureRoot & "/release.json", "{}" );
				expect( locator.configFile( fixtureRoot ) ).toBe( fixtureRoot & "/release.json" );
			} );

			it( "stops with upgrade instructions for 1.x and 2.x settings files", function(){
				fileWrite( fixtureRoot & "/build.json", "{}" );
				expect( function(){
					locator.configFile( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "build\.json" );

				fileDelete( fixtureRoot & "/build.json" );
				directoryCreate( fixtureRoot & "/build", true, true );
				fileWrite( fixtureRoot & "/build/build.json", "{}" );
				expect( function(){
					locator.configFile( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "build/build\.json" );

				// release.json wins as soon as it exists.
				fileWrite( fixtureRoot & "/release.json", "{}" );
				expect( locator.configFile( fixtureRoot ) ).toBe( fixtureRoot & "/release.json" );
			} );
		} );
	}
}
