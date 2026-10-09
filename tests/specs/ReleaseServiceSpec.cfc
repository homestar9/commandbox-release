/** Checks how release code reads remote tag results without using a real remote. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Remote release tag status", function(){
			beforeEach( function(){
				release = prepareMock( model( "ReleaseService" ) );
				config  = createStub();
				release.$property( propertyName = "config", propertyScope = "variables", mock = config );
				release.$property( propertyName = "settings", propertyScope = "variables", mock = { remote : "origin" } );
				makePublic( release, "remoteTagState" );
			} );

			it( "reads a lightweight tag commit", function(){
				config.$( "execNative", { exitCode : 0, output : "abc123" & chr( 9 ) & "refs/tags/v1.0.0" } );
				var state = release.remoteTagState( "v1.0.0" );
				expect( state.status ).toBe( "present" );
				expect( state.commit ).toBe( "abc123" );
			} );

			it( "uses the resolved commit for an annotated tag", function(){
				config.$(
					"execNative",
					{
						exitCode : 0,
						output   : "tag999" & chr( 9 ) & "refs/tags/v1.0.0" & chr( 10 )
							& "commit42" & chr( 9 ) & "refs/tags/v1.0.0^{}"
					}
				);
				expect( release.remoteTagState( "v1.0.0" ).commit ).toBe( "commit42" );
			} );

			it( "reports a tag that is missing from origin", function(){
				config.$( "execNative", { exitCode : 2, output : "" } );
				var state = release.remoteTagState( "v1.0.0" );
				expect( state.status ).toBe( "missing" );
				expect( state.commit ).toBe( "" );
			} );

			it( "reports when origin cannot be checked", function(){
				config.$( "execNative", { exitCode : 128, output : "fatal: could not read from remote" } );
				var state = release.remoteTagState( "v1.0.0" );
				expect( state.status ).toBe( "unknown" );
				expect( state.output ).toInclude( "could not read" );
			} );
		} );
	}
}
