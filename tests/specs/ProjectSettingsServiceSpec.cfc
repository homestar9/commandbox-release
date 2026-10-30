/** Checks project defaults and display values without reading files. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "ProjectSettingsService", function(){
			beforeEach( function(){
				projectSettings = model( "ProjectSettingsService" );
			} );

			it( "detects a module from the package type or ModuleConfig.cfc", function(){
				expect( projectSettings.isModule( { type : "commandbox-modules" } ) ).toBeTrue();
				expect( projectSettings.isModule( { type : "mvc" } ) ).toBeFalse();
				expect( projectSettings.isModule( {} ) ).toBeFalse();
				expect( projectSettings.isModule( {}, true ) ).toBeTrue();
			} );

			it( "reads test runner settings in each supported format", function(){
				expect( projectSettings.detectTestRunner( { testbox : { runner : "http://one/tests" } } ) )
					.toBe( "http://one/tests" );
				expect( projectSettings.detectTestRunner( { testbox : { runner : [ "http://two/tests" ] } } ) )
					.toBe( "http://two/tests" );
				expect( projectSettings.detectTestRunner( { testbox : { runner : { local : "http://three/tests" } } } ) )
					.toBe( "http://three/tests" );
				expect( projectSettings.detectTestRunner( {} ) )
					.toBe( "/tests/runner.cfm" );
			} );

			it( "suggests a test command only for a CommandBox module with a test script and no runner URL", function(){
				var script = { test : "task run taskFile=tests/Run.cfc" };
				expect( projectSettings.detectTestCommand( { type : "commandbox-modules", scripts : script } ) )
					.toBe( "run-script test" );
				expect( projectSettings.detectTestCommand( { type : "commandbox-modules", scripts : { build : "x" } } ) )
					.toBe( "" );
				expect( projectSettings.detectTestCommand( { type : "commandbox-modules", scripts : script, testbox : { runner : "http://one/tests" } } ) )
					.toBe( "" );
				expect( projectSettings.detectTestCommand( { type : "commandbox-modules", scripts : script, testbox : { runner : [ "http://two/tests" ] } } ) )
					.toBe( "" );
				expect( projectSettings.detectTestCommand( { type : "modules", scripts : script } ) )
					.toBe( "" );
				expect( projectSettings.detectTestCommand( {} ) ).toBe( "" );
			} );

			it( "recommends different ignore patterns for modules and applications", function(){
				var moduleIgnores = arrayToList( projectSettings.recommendedIgnores( true ) );
				var appIgnores    = arrayToList( projectSettings.recommendedIgnores( false ) );

				expect( moduleIgnores ).toInclude( "/modules/" );
				expect( moduleIgnores ).toInclude( "**/.*" );
				expect( moduleIgnores ).notToInclude( "!/.htaccess" );

				expect( appIgnores ).notToInclude( "/modules/" );
				expect( appIgnores ).toInclude( "**/.*" );
				expect( appIgnores ).toInclude( "!/.htaccess" );
				expect( appIgnores ).toInclude( "!/.well-known/" );

				for ( var patterns in [ moduleIgnores, appIgnores ] ) {
					expect( patterns ).toInclude( "/tests/" );
					expect( patterns ).toInclude( "**/*.bak" );
					expect( patterns ).toInclude( "/node_modules/" );
					expect( patterns ).toInclude( "/package-lock.json" );
				}
			} );

			it( "adds only the missing ignore patterns and keeps the existing order", function(){
				var outcome = projectSettings.mergeIgnores( [ "/custom/", "/tests/" ], [ "/tests/", "**/.*" ] );
				expect( arrayToList( outcome.ignore ) ).toBe( "/custom/,/tests/,**/.*" );
				expect( arrayToList( outcome.added ) ).toBe( "**/.*" );

				var again = projectSettings.mergeIgnores( outcome.ignore, [ "/tests/", "**/.*" ] );
				expect( arrayLen( again.added ) ).toBe( 0 );

				var fromNothing = projectSettings.mergeIgnores( "not a list", [ "/tests/" ] );
				expect( arrayToList( fromNothing.ignore ) ).toBe( "/tests/" );
			} );

			it( "finds install scripts that empty the ignore list", function(){
				var template = "pathExists .env || cp .env.example .env && package set ignore=[]";

				var found = projectSettings.ignoreClearingScripts( { scripts : { postInstall : template, test : "x" } } );
				expect( found ).toBe( [ { name : "postInstall", template : true } ] );

				var spaced = "  pathExists .env  ||  cp .env.example .env &&   package set ignore=[] ";
				expect( projectSettings.ignoreClearingScripts( { scripts : { postInstall : spaced } } )[ 1 ].template ).toBeTrue();

				var lowerCase = deserializeJSON( '{ "scripts" : { "postinstall" : "#template#" } }' );
				expect( projectSettings.ignoreClearingScripts( lowerCase )[ 1 ].template ).toBeTrue();

				var custom = projectSettings.ignoreClearingScripts( { scripts : { preInstall : "package set ignore=[] && echo done" } } );
				expect( custom ).toBe( [ { name : "preInstall", template : false } ] );
				expect( projectSettings.ignoreClearingScripts( { scripts : { onInstall : template } } )[ 1 ].template ).toBeFalse();
			} );

			it( "skips scripts that do not empty the ignore list", function(){
				var template = "pathExists .env || cp .env.example .env && package set ignore=[]";
				expect( projectSettings.ignoreClearingScripts( { scripts : { postInstall : "pathExists .env || cp .env.example .env" } } ) ).toBeEmpty();
				expect( projectSettings.ignoreClearingScripts( { scripts : { "reset:ignore" : template } } ) ).toBeEmpty();
				expect( projectSettings.ignoreClearingScripts( { scripts : { postInstall : [ "package set ignore=[]" ] } } ) ).toBeEmpty();
				expect( projectSettings.ignoreClearingScripts( { scripts : "postInstall" } ) ).toBeEmpty();
				expect( projectSettings.ignoreClearingScripts( {} ) ).toBeEmpty();
			} );

			it( "gets engine names from cfengine, server name, or filename", function(){
				expect( projectSettings.engineName( "server-lucee.json", { app : { cfengine : "lucee@5" } } ) )
					.toBe( "Lucee 5" );
				expect( projectSettings.engineName( "server-local.json", { name : "Local Adobe" } ) )
					.toBe( "Local Adobe" );
				expect( projectSettings.engineName( "server-boxlang-cfml@1.json" ) )
					.toBe( "Boxlang 1" );
			} );
		} );
	}
}
