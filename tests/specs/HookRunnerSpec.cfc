/** Checks how HookRunner runs the hooks in release.json. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "HookRunner", function(){
			beforeEach( function(){
				lines         = [];
				processRunner = createStub();
				hookRunner    = prepareMock( model( "HookRunner" ) );
				hookRunner.usePrinter( createRecordingPrinter( lines ) );
				hookRunner.$property( propertyName = "processRunner", propertyScope = "variables", mock = processRunner );
				hookRunner.$property( propertyName = "root", propertyScope = "variables", mock = "D:/projects/sample" );
				useHook( "deploybot env push --yes" );
			} );

			it( "runs the hook with box in the project root and shows its output", function(){
				processRunner.$( method = "run", callback = function(){
					arguments.onLine( "No changes." );
					return { exitCode : 0, output : "No changes." };
				} );

				expect( hookRunner.run( "beforePublish" ) ).toBeTrue();
				var call = processRunner.$callLog().run[ 1 ];
				expect( call.name ).toBe( "box" );
				expect( call.args ).toBe( [ "deploybot env push --yes" ] );
				expect( call.workingDirectory ).toBe( "D:/projects/sample" );
				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( "Running: box deploybot env push --yes" );
				expect( output ).toInclude( "No changes." );
				expect( output ).toInclude( "The beforePublish command finished." );
			} );

			it( "passes a command with quotes and && as one argument", function(){
				useHook( "run-script notify && echo ""Released 1.0.0""" );
				processRunner.$( "run", { exitCode : 0, output : "" } );

				hookRunner.run( "beforePublish" );
				expect( processRunner.$callLog().run[ 1 ].args ).toBe( [ "run-script notify && echo ""Released 1.0.0""" ] );
			} );

			it( "does nothing when the hook is off", function(){
				useHook( "" );
				processRunner.$( "run", { exitCode : 0, output : "" } );

				expect( hookRunner.run( "beforePublish" ) ).toBeFalse();
				expect( processRunner.$count( "run" ) ).toBe( 0 );
				expect( lines ).toBeEmpty();
			} );

			it( "only shows the hook in a practice run", function(){
				processRunner.$( "run", { exitCode : 0, output : "" } );

				expect( hookRunner.run( name = "beforePublish", dryRun = true ) ).toBeFalse();
				expect( processRunner.$count( "run" ) ).toBe( 0 );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "box deploybot env push --yes" );
			} );

			it( "skips the hook when asked", function(){
				processRunner.$( "run", { exitCode : 0, output : "" } );

				expect( hookRunner.run( name = "beforePublish", skip = true ) ).toBeFalse();
				expect( processRunner.$count( "run" ) ).toBe( 0 );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "The beforePublish command was skipped (requested with skipHooks)" );
			} );

			it( "stops with the command and its exit code when it fails", function(){
				processRunner.$( "run", { exitCode : 1, output : "Push failed." } );
				processRunner.$( "commandExists", true );

				expect( function(){
					hookRunner.run( "beforePublish" );
				} ).toThrow(
					type  = "Release.Stop",
					regex = "The beforePublish command failed: box deploybot env push --yes \(exit code 1\)\. Nothing was published\."
				);
			} );

			it( "explains when box cannot be found", function(){
				processRunner.$( "run", { exitCode : 127, output : "Could not start 'box'" } );
				processRunner.$( "commandExists", false );

				expect( function(){
					hookRunner.run( "beforePublish" );
				} ).toThrow( type = "Release.Stop", regex = "box was not found" );
			} );
		} );

		describe( "Recovery note after the beforePublish command", function(){
			it( "says that the command already ran only when it ran", function(){
				var release = prepareMock( model( "ReleaseService" ) );
				expect( release.hookNote() ).toBe( "" );

				release.$property( propertyName = "beforePublishRan", propertyScope = "variables", mock = true );
				expect( release.hookNote() ).toBe( "The beforePublish command already ran. " );
			} );
		} );
	}

	/** Sets the beforePublish command in the runner's settings. */
	private void function useHook( required string hookCommand ){
		hookRunner.$property(
			propertyName  = "settings",
			propertyScope = "variables",
			mock          = { hooks : { beforePublish : arguments.hookCommand } }
		);
	}

	/** Returns a print buffer stub that saves every printed line in the lines array. */
	private any function createRecordingPrinter( required array lines ){
		var printer  = createStub();
		var recorded = arguments.lines;
		for ( var method in [ "line", "blueLine", "boldBlueLine", "greenLine", "yellowLine", "boldYellowLine" ] ) {
			printer.$( method = method, callback = function( text = "" ){
				recorded.append( arguments.text );
				return printer;
			} );
		}
		printer.$( "toConsole", printer );
		return printer;
	}
}
