/** Checks the module name, package exclusions, and registered commands. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Module", function(){
			it( "uses its package slug as the CommandBox module name", function(){
				var packageData  = deserializeJSON( fileRead( repoRoot() & "/box.json" ) );
				var moduleConfig = createObject( "component", "commandbox-release.ModuleConfig" );

				expect( packageData.type ).toBe( "commandbox-modules" );
				expect( packageData.slug ).toBe( "commandbox-release" );
				expect( moduleConfig.cfmapping ).toBe( packageData.slug );
				expect( moduleConfig.modelNamespace ).toBe( packageData.slug );
			} );

			it( "excludes tests and temporary files from the package", function(){
				var ignore = arrayToList( deserializeJSON( fileRead( repoRoot() & "/box.json" ) ).ignore );
				expect( ignore ).toInclude( "/tests/" );
				expect( ignore ).toInclude( "/testbox/" );
				expect( ignore ).toInclude( "/.test-work/" );
				expect( ignore ).toInclude( "/release.json" );
			} );

			it( "keeps every shipped file out of its own ignore list", function(){
				var ignore  = deserializeJSON( fileRead( repoRoot() & "/box.json" ) ).ignore;
				var matcher = application.wirebox.getInstance( "PathPatternMatcher@globber" );
				for ( var shipped in [ "models/", "commands/", "commands/release/", "templates/", "ModuleConfig.cfc", "box.json" ] ) {
					expect( matcher.matchPatterns( ignore, shipped ) ).toBeFalse( "#shipped# must not be ignored" );
				}
			} );

			it( "registers all release commands", function(){
				var hierarchy = application.wirebox.getInstance( "CommandService" ).getCommandHierarchy();
				expect( hierarchy ).toHaveKey( "release" );

				var names = [];
				for ( var key in hierarchy.release ) {
					if ( left( key, 1 ) != "$" ) {
						names.append( key );
					}
				}
				names.sort( "textnocase" );
				expect( arrayToList( names ) ).toBe( "bump,check,gitflow,help,init,notes,package,publish,resume,test" );
			} );
		} );
	}
}
