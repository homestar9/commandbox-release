/** Checks settings, old settings files, and required module versions. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "ProjectConfig", function(){
			beforeEach( function(){
				fixtureRoot = createTempProject();
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			it( "loads defaults and reads the test runner from box.json", function(){
				writePackage( { name : "Sample", slug : "sample", version : "1.2.3", testbox : { runner : "http://localhost:61000/tests" } } );
				writeSettings( {} );

				var config   = model( "ProjectConfig" ).load( fixtureRoot );
				var settings = config.getSettings();
				expect( settings.branch ).toBe( "main" );
				expect( settings.testRunner ).toBe( "http://localhost:61000/tests" );
				expect( config.slug() ).toBe( "sample" );
				expect( config.version() ).toBe( "1.2.3" );
				expect( config.probeUrl() ).toBe( "http://localhost:61000/" );
				expect( config.configPath() ).toBe( fixtureRoot & "/release.json" );
			} );

			it( "keeps other defaults when one nested setting changes", function(){
				writePackage( { name : "Sample", version : "1.0.0", type : "modules" } );
				writeSettings( { publish : { github : false } } );

				var settings = model( "ProjectConfig" ).load( fixtureRoot ).getSettings();
				expect( settings.publish.github ).toBeFalse();
				expect( settings.publish.forgebox ).toBeTrue();
			} );

			it( "disables ForgeBox by default when box.json does not describe a module", function(){
				writePackage( { name : "Sample", version : "1.0.0", type : "mvc" } );
				writeSettings( {} );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().publish.forgebox ).toBeFalse();
			} );

			it( "enables ForgeBox by default when the project has ModuleConfig.cfc", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				fileWrite( fixtureRoot & "/ModuleConfig.cfc", "component {}" );
				writeSettings( {} );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().publish.forgebox ).toBeTrue();
			} );

			it( "keeps an explicit ForgeBox setting", function(){
				writePackage( { name : "Sample", version : "1.0.0", type : "mvc" } );
				writeSettings( { publish : { forgebox : true } } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().publish.forgebox ).toBeTrue();
			} );

			it( "reports invalid settings with a clear message", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { branch : "" } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "branch" );
			} );

			it( "uses origin as the default remote and accepts another remote name", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( {} );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().remote ).toBe( "origin" );

				writeSettings( { remote : "github" } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().remote ).toBe( "github" );
			} );

			it( "rejects remote values that are not Git remote names", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				for ( var badRemote in [ "", " ", "my remote", "--upload-pack=x", "-x", "a/b", "a:b" ] ) {
					writeSettings( { remote : badRemote } );
					expect( function(){
						model( "ProjectConfig" ).load( fixtureRoot );
					} ).toThrow( type = "Release.Config", regex = "remote" );
				}
				writeSettings( { remote : [ "origin" ] } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "remote" );
			} );

			it( "rejects build folders outside the project", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				for ( var badFolder in [ "", " ", ".", "./", "/", "/tmp", "C:/build", "..", "../out", "build/../..", "a/./b" ] ) {
					writeSettings( { stagingDir : badFolder } );
					expect( function(){
						model( "ProjectConfig" ).load( fixtureRoot );
					} ).toThrow( type = "Release.Config", regex = "stagingDir" );
				}
				writeSettings( { artifactsDir : "../artifacts" } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "artifactsDir" );

				writeSettings( { stagingDir : "build/tmp/", artifactsDir : ".out" } );
				var settings = model( "ProjectConfig" ).load( fixtureRoot ).getSettings();
				expect( settings.stagingDir ).toBe( "build/tmp/" );
				expect( settings.artifactsDir ).toBe( ".out" );
			} );

			it( "stops with upgrade instructions when the project still has build.json", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				fileWrite( fixtureRoot & "/build.json", serializeJSON( { branch : "master" } ) );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "Upgrading from 1\.x or 2\.x" );
			} );

			it( "stops when release.json still contains a 2.x setting", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { excludesAdd : [ "^private$" ] } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "excludesAdd" );
			} );

			it( "uses defaults when the project has no settings file", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				var config = model( "ProjectConfig" ).load( fixtureRoot );
				expect( config.configPath() ).toBe( "" );
				expect( config.getSettings() ).notToHaveKey( "projectType" );
			} );

			it( "stops when the project requires a newer module", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { requires : "99.0.0" } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.TooOld", regex = "box update commandbox-release" );

				writeSettings( { requires : "0.0.1" } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().requires ).toBe( "0.0.1" );
			} );

			it( "reads the installed module version", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).moduleVersion() ).toBe( moduleVersion() );
			} );

			it( "has no test command by default", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( {} );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().testCommand ).toBe( "" );
			} );

			it( "does not check testRunner when a test command is set", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { testRunner : "not a URL" } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "testRunner" );

				writeSettings( { testRunner : "not a URL", testCommand : "run-script test" } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().testCommand ).toBe( "run-script test" );
			} );

			it( "trims the test command and removes a leading box", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { testCommand : "  box run-script test " } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().testCommand ).toBe( "run-script test" );

				writeSettings( { testCommand : "BOX   task run taskFile=tests/Run.cfc" } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().testCommand ).toBe( "task run taskFile=tests/Run.cfc" );
			} );

			it( "rejects a test command that is not one line of text", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				for ( var badCommand in [ [ "run-script", "test" ], { name : "test" }, "run-script test" & chr( 10 ) & "echo done" ] ) {
					writeSettings( { testCommand : badCommand } );
					expect( function(){
						model( "ProjectConfig" ).load( fixtureRoot );
					} ).toThrow( type = "Release.Config", regex = "testCommand must be one CommandBox command" );
				}
			} );

			it( "rejects a test command together with engines", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( {
					testCommand : "run-script test",
					engines     : [ { name : "Lucee 5", configFile : "server-lucee@5.json" } ]
				} );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "both testCommand and engines" );

				writeSettings( { testCommand : "run-script test", engines : [] } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().engines ).toBeEmpty();
			} );

			it( "has no beforePublish hook by default", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( {} );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().hooks ).toBe( { beforePublish : "" } );

				writeSettings( { hooks : {} } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().hooks.beforePublish ).toBe( "" );
			} );

			it( "trims a hook and removes a leading box", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { hooks : { beforePublish : "  box deploybot env push --yes " } } );
				expect( model( "ProjectConfig" ).load( fixtureRoot ).getSettings().hooks.beforePublish ).toBe( "deploybot env push --yes" );
			} );

			it( "rejects hooks that are not a struct", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { hooks : "deploybot env push --yes" } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "hooks must look like" );
			} );

			it( "rejects an unknown hook name", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { hooks : { afterPublish : "run-script notify" } } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "unknown hook ""afterPublish"". The supported hook is: beforePublish" );
			} );

			it( "rejects a hook that is not one line of text", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				for ( var badCommand in [ [ "deploybot", "env", "push" ], { name : "push" }, "deploybot env push" & chr( 10 ) & "echo done" ] ) {
					writeSettings( { hooks : { beforePublish : badCommand } } );
					expect( function(){
						model( "ProjectConfig" ).load( fixtureRoot );
					} ).toThrow( type = "Release.Config", regex = "hooks.beforePublish must be one CommandBox command" );
				}
			} );

			it( "has no prerelease branches by default", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( {} );
				var config = model( "ProjectConfig" ).load( fixtureRoot );
				expect( config.getSettings().prereleaseBranches ).toBe( [] );
				expect( config.isPrereleaseBranch( "develop" ) ).toBeFalse();
				expect( config.publishBranchFor( "1.1.0-alpha.1", "develop" ) ).toBe( "main" );
			} );

			it( "rejects prerelease branches that are not whole branch names", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				for ( var bad in [ "develop", [ "" ], [ " " ], [ "HEAD" ], [ "-x" ], [ "a b" ], [ "*" ], [ "release/*" ], [ { name : "develop" } ] ] ) {
					writeSettings( { prereleaseBranches : bad } );
					expect( function(){
						model( "ProjectConfig" ).load( fixtureRoot );
					} ).toThrow( type = "Release.Config", regex = "prereleaseBranches must be a list of branch names" );
				}
			} );

			it( "rejects the production branch as a prerelease branch", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { branch : "master", prereleaseBranches : [ "develop", "master" ] } );
				expect( function(){
					model( "ProjectConfig" ).load( fixtureRoot );
				} ).toThrow( type = "Release.Config", regex = "cannot list production branch master" );
			} );

			it( "chooses the publish branch from the version and the current branch", function(){
				writePackage( { name : "Sample", version : "1.0.0" } );
				writeSettings( { branch : "master", prereleaseBranches : [ "develop", "release/next" ] } );
				var config = model( "ProjectConfig" ).load( fixtureRoot );

				expect( config.isPrereleaseBranch( "develop" ) ).toBeTrue();
				expect( config.isPrereleaseBranch( "release/next" ) ).toBeTrue();
				expect( config.isPrereleaseBranch( "Develop" ) ).toBeFalse();
				expect( config.publishBranchFor( "2.1.0-alpha.1", "develop" ) ).toBe( "develop" );
				expect( config.publishBranchFor( "2.1.0", "develop" ) ).toBe( "master" );
				expect( config.publishBranchFor( "2.1.0-alpha.1", "feature/thing" ) ).toBe( "master" );
				expect( config.publishBranchFor( "2.1.0+build-7", "develop" ) ).toBe( "master" );
				expect( config.publishBranchFor( "2.1.0-alpha.1", "HEAD" ) ).toBe( "master" );
			} );

			it( "reads the box.json ignore list and tolerates a bad one", function(){
				writePackage( { name : "Sample", version : "1.0.0", ignore : [ "/tests/", " **/*.bak ", 5, "" ] } );
				expect( arrayToList( model( "ProjectConfig" ).load( fixtureRoot ).packageIgnores() ) ).toBe( "/tests/,**/*.bak,5" );

				writePackage( { name : "Sample", version : "1.0.0" } );
				expect( arrayLen( model( "ProjectConfig" ).load( fixtureRoot ).packageIgnores() ) ).toBe( 0 );

				writePackage( { name : "Sample", version : "1.0.0", ignore : "not a list" } );
				expect( arrayLen( model( "ProjectConfig" ).load( fixtureRoot ).packageIgnores() ) ).toBe( 0 );
			} );
		} );
	}

	private void function writePackage( required struct packageData ){
		fileWrite( fixtureRoot & "/box.json", serializeJSON( arguments.packageData ) );
	}

	private void function writeSettings( required struct settings ){
		fileWrite( fixtureRoot & "/release.json", serializeJSON( arguments.settings ) );
	}
}
