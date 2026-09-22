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
