/** Checks every supported semantic version change without reading project files. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "VersionService", function(){
			beforeEach( function(){
				versionService = model( "VersionService" );
			} );

			it( "lists every version level accepted by VersionBumper.cfc", function(){
				expect( versionService.supportedLevels() )
					.toBe( "major,minor,patch,prerelease,premajor,preminor,prepatch,none" );
			} );

			it( "reads the main, prerelease, and build parts", function(){
				var parsedVersion = versionService.parseVersion( "1.2.3-beta.4+build7" );
				expect( parsedVersion.major ).toBe( 1 );
				expect( parsedVersion.minor ).toBe( 2 );
				expect( parsedVersion.patch ).toBe( 3 );
				expect( parsedVersion.prerelease ).toBe( "beta.4" );
				expect( parsedVersion.build ).toBe( "build7" );
			} );

			it( "changes normal major, minor, and patch versions", function(){
				expect( versionService.nextVersion( "1.2.3", "major" ) ).toBe( "2.0.0" );
				expect( versionService.nextVersion( "1.2.3", "minor" ) ).toBe( "1.3.0" );
				expect( versionService.nextVersion( "1.2.3", "patch" ) ).toBe( "1.2.4" );
			} );

			it( "finishes a prerelease at its target version", function(){
				expect( versionService.nextVersion( "2.0.0-beta.3", "major" ) ).toBe( "2.0.0" );
				expect( versionService.nextVersion( "1.2.0-beta.3", "minor" ) ).toBe( "1.2.0" );
				expect( versionService.nextVersion( "1.2.3-beta.3", "patch" ) ).toBe( "1.2.3" );
				expect( versionService.nextVersion( "1.2.3-beta.3", "minor" ) ).toBe( "1.3.0" );
			} );

			it( "starts prereleases with a selected label", function(){
				expect( versionService.nextVersion( "1.2.3", "premajor" ) ).toBe( "2.0.0-beta.1" );
				expect( versionService.nextVersion( "1.2.3", "preminor", "alpha" ) ).toBe( "1.3.0-alpha.1" );
				expect( versionService.nextVersion( "1.2.3", "prepatch", "rc" ) ).toBe( "1.2.4-rc.1" );
			} );

			it( "updates prerelease numbers and labels", function(){
				expect( versionService.nextVersion( "1.2.3-beta.4", "prerelease" ) ).toBe( "1.2.3-beta.5" );
				expect( versionService.nextVersion( "1.2.3-beta", "prerelease" ) ).toBe( "1.2.3-beta.1" );
				expect( versionService.nextVersion( "1.2.3-alpha.7", "prerelease", "beta" ) ).toBe( "1.2.3-beta.1" );
			} );

			it( "compares versions by Semantic Versioning order", function(){
				expect( versionService.compareVersions( "1.10.0", "1.9.9" ) ).toBe( 1 );
				expect( versionService.compareVersions( "1.9.9", "1.10.0" ) ).toBe( -1 );
				expect( versionService.compareVersions( "1.0.0", "1.0.0-beta.1" ) ).toBe( 1 );
				expect( versionService.compareVersions( "1.0.0-beta.2", "1.0.0-beta.1" ) ).toBe( 1 );
				expect( versionService.compareVersions( "1.0.0-beta.11", "1.0.0-beta.2" ) ).toBe( 1 );
				expect( versionService.compareVersions( "1.0.0-rc.1", "1.0.0-beta.9" ) ).toBe( 1 );
				expect( versionService.compareVersions( "1.0.0-beta", "1.0.0-beta.1" ) ).toBe( -1 );
				expect( versionService.compareVersions( "1.2.3", "1.2.3" ) ).toBe( 0 );
				expect( versionService.compareVersions( "1.2.3+build7", "1.2.3+build9" ) ).toBe( 0 );
			} );

			it( "returns the highest version and ignores prereleases by default", function(){
				var versions = [ "1.9.9", "1.10.0", "2.0.0-beta.1", "not-a-version", "0.5.0" ];
				expect( versionService.highestVersion( versions ) ).toBe( "1.10.0" );
				expect( versionService.highestVersion( versions, true ) ).toBe( "2.0.0-beta.1" );
				expect( versionService.highestVersion( [ "junk" ] ) ).toBe( "" );
			} );

			it( "stops a prerelease update on a final version", function(){
				expect( function(){
					versionService.nextVersion( "1.2.3", "prerelease" );
				} ).toThrow( type = "Release.Version.NotPrerelease" );
			} );
		} );
	}
}
