/**
 * Checks how release init handles the ColdBox template's postInstall script. The integration
 * box cannot answer questions, so this spec passes the answer to ProjectInstaller.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "ProjectInstaller install scripts", function(){
			beforeEach( function(){
				fixtureRoot = createTempProject();
				lines       = [];
				template    = "pathExists .env || cp .env.example .env && package set ignore=[]";
				writeJSON( fixtureRoot & "/release.json", {} );
				fileWrite(
					fixtureRoot & "/box.json",
					serializeJSON( {
						"name"    : "Site",
						"slug"    : "site",
						"version" : "1.0.0",
						"type"    : "mvc",
						"ignore"  : [ "/custom/" ],
						"scripts" : { "postInstall" : template, "format" : "cfformat run" }
					} )
				);
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			it( "removes only the template script when the user agrees", function(){
				installer().run( root = fixtureRoot, answers = { removeTemplateScript : true } );

				var packageData = deserializeJSON( fileRead( fixtureRoot & "/box.json" ) );
				expect( packageData.scripts ).notToHaveKey( "postInstall" );
				expect( packageData.scripts.format ).toBe( "cfformat run" );
				expect( packageData.ignore[ 1 ] ).toBe( "/custom/" );
				expect( arrayToList( packageData.ignore ) ).toInclude( "/tests/" );

				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "update  box.json scripts (removed postInstall)" );
				expect( output ).toInclude( "run in box: cp .env.example .env" );
				expect( output ).notToInclude( "note  The box.json postInstall script" );
			} );

			it( "keeps the template script and prints a note without an answer", function(){
				installer().run( root = fixtureRoot );

				var packageData = deserializeJSON( fileRead( fixtureRoot & "/box.json" ) );
				expect( packageData.scripts.postInstall ).toBe( template );

				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "note  The box.json postInstall script runs ""package set ignore""" );
				expect( output ).toInclude( "To remove the script, run: box release init" );
			} );

			it( "never removes a changed script", function(){
				var packageData = deserializeJSON( fileRead( fixtureRoot & "/box.json" ) );
				packageData.scripts.postInstall = template & " && echo done";
				fileWrite( fixtureRoot & "/box.json", serializeJSON( packageData ) );

				installer().run( root = fixtureRoot, answers = { removeTemplateScript : true } );

				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).scripts ).toHaveKey( "postInstall" );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "Remove ""package set ignore"" from the postInstall script in box.json." );
			} );
		} );
	}

	private any function installer(){
		return model( "ProjectInstaller" ).usePrinter( createRecordingPrinter( lines ) );
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	private any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "boldLine", "greenLine", "yellowLine", "boldGreenLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}
}
