/**
 * Checks the branch gates of ReleaseService without Git. A stub repository answers
 * currentBranch(), so each case runs in milliseconds. GitflowSpec covers the same rules
 * end to end in temporary projects.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "ReleaseService branch gates", function(){
			beforeEach( function(){
				fixtureRoot = createTempProject();
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			describe( "publish <level> on a prerelease branch", function(){
				it( "passes a prerelease target", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.1.0-alpha.1" );
					service.checkBranchForBump( "2.1.0-alpha.1", "preminor", false );
					expect( output() ).toInclude( "ok  on prerelease branch develop" );
				} );

				it( "stops a stable target and shows both ways forward", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.1.0" );
					expect( function(){
						service.checkBranchForBump( "2.1.0", "minor", false );
					} ).toThrow( type = "Release.Stop", regex = "develop can publish only prerelease versions, and 2\.1\.0 is stable\. Stable versions publish from production branch master\." );
					expect( output() ).toInclude( "box release gitflow minor" );
					expect( output() ).toInclude( "box release publish preminor alpha" );
				} );

				it( "only warns about a stable target in a practice run", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.1.0" );
					service.checkBranchForBump( "2.1.0", "minor", true );
					expect( output() ).toInclude( "A real run stops: develop can publish only prerelease versions." );
				} );

				it( "suggests minor for the none level", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.0.0" );
					expect( function(){
						service.checkBranchForBump( "2.0.0", "none", false );
					} ).toThrow( type = "Release.Stop" );
					expect( output() ).toInclude( "box release gitflow minor" );
					expect( output() ).toInclude( "box release publish preminor alpha" );
					expect( output() ).notToInclude( "prenone" );
				} );

				it( "suggests the next prerelease when the level would finish the current one", function(){
					var service = gates( "develop", "2.1.0-alpha.3" );
					service.usePublishBranch( "2.1.0" );
					expect( function(){
						service.checkBranchForBump( "2.1.0", "minor", false );
					} ).toThrow( type = "Release.Stop" );
					expect( output() ).toInclude( "box release publish prerelease" );
					expect( output() ).notToInclude( "preminor alpha" );
				} );

				it( "suggests a new prerelease when the level targets another version", function(){
					var service = gates( "develop", "2.1.0-alpha.3" );
					service.usePublishBranch( "3.0.0" );
					expect( function(){
						service.checkBranchForBump( "3.0.0", "major", false );
					} ).toThrow( type = "Release.Stop" );
					expect( output() ).toInclude( "box release publish premajor alpha" );
					expect( output() ).notToInclude( "box release publish prerelease" );
				} );
			} );

			describe( "publish <level> on other branches", function(){
				it( "passes on production for any version", function(){
					var service = gates( "master", "2.1.0-alpha.3" );
					service.usePublishBranch( "2.1.0-alpha.4" );
					service.checkBranchForBump( "2.1.0-alpha.4", "prerelease", false );
					expect( output() ).toInclude( "ok  on production branch master" );
				} );

				it( "stops on a branch that is not listed and explains the setting for a prerelease", function(){
					var service = gates( "feature/thing", "2.0.0" );
					service.usePublishBranch( "2.1.0-alpha.1" );
					expect( function(){
						service.checkBranchForBump( "2.1.0-alpha.1", "preminor", false );
					} ).toThrow( type = "Release.Stop", regex = "must run from production branch master" );
					expect( output() ).toInclude( "To publish prereleases from feature/thing, add it to ""prereleaseBranches"" in release.json." );
				} );

				it( "does not mention the setting for a stable target", function(){
					var service = gates( "feature/thing", "2.0.0" );
					service.usePublishBranch( "2.1.0" );
					expect( function(){
						service.checkBranchForBump( "2.1.0", "minor", false );
					} ).toThrow( type = "Release.Stop", regex = "must run from production branch master" );
					expect( output() ).notToInclude( "prereleaseBranches" );
				} );
			} );

			describe( "publish without a level on a prerelease branch", function(){
				it( "stops a stable version before the tag check", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.0.0" );
					expect( function(){
						service.checkStableOnPrereleaseBranch( "2.0.0", false );
					} ).toThrow( type = "Release.Stop", regex = "develop can publish only prerelease versions, and 2\.0\.0 is stable" );
					expect( output() ).toInclude( "box release publish preminor alpha" );
					expect( output() ).toInclude( "box release gitflow minor" );
				} );

				it( "passes a prerelease version", function(){
					var service = gates( "develop", "2.1.0-alpha.1" );
					service.usePublishBranch( "2.1.0-alpha.1" );
					service.checkStableOnPrereleaseBranch( "2.1.0-alpha.1", false );
					expect( output() ).toBe( "" );
				} );

				it( "leaves other branches to the usual branch check", function(){
					var service = gates( "feature/thing", "2.0.0" );
					service.usePublishBranch( "2.0.0" );
					service.checkStableOnPrereleaseBranch( "2.0.0", false );
					expect( output() ).toBe( "" );
				} );

				it( "only warns in a practice run", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.0.0" );
					service.checkStableOnPrereleaseBranch( "2.0.0", true );
					expect( output() ).toInclude( "A real run stops: develop can publish only prerelease versions." );
				} );

				it( "skips the check when the caller chose the publish branch", function(){
					var service = gates( "develop", "2.0.0" );
					service.usePublishBranch( "2.1.0", "master" );
					service.checkStableOnPrereleaseBranch( "2.1.0", false );
					expect( output() ).toBe( "" );
				} );
			} );
		} );
	}

	// FIXTURE HELPERS

	/**
	 * Returns a ReleaseService for a project on the given branch with the given box.json
	 * version. develop is the only prerelease branch. The private gates are public on it.
	 */
	private any function gates( required string branch, required string version ){
		writeJSON( fixtureRoot & "/box.json", { name : "Sample", slug : "sample", version : arguments.version } );
		writeJSON( fixtureRoot & "/release.json", {
			branch             : "master",
			prereleaseBranches : [ "develop" ],
			runTests           : false,
			publish            : { forgebox : false, github : false }
		} );
		lines = [];

		var repository = createStub();
		repository.$( "currentBranch", arguments.branch );

		var service = prepareMock( model( "ReleaseService" ).forProject( model( "ProjectConfig" ).load( fixtureRoot ) ) );
		service.$property( propertyName = "repositoryService", propertyScope = "variables", mock = repository );
		service.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( lines ) );
		for ( var name in [ "usePublishBranch", "checkBranchForBump", "checkStableOnPrereleaseBranch" ] ) {
			makePublic( service, name );
		}
		return service;
	}

	/** Returns everything the service printed, one line per printed call. */
	private string function output(){
		return lines.toList( chr( 10 ) );
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	private any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "boldLine", "greenLine", "yellowLine", "boldYellowLine", "redLine", "boldBlueLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}
}
