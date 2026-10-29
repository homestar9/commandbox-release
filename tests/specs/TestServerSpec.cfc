/**
 * Checks how TestServer turns testRunner into URLs. A stub replaces the CommandBox server
 * service, so no server starts and the server list is not read.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Test server URLs", function(){
			beforeEach( function(){
				servers       = {};
				running       = {};
				lookups       = [];
				serverService = createStub();
				serverService.$( method = "resolveServerDetails", callback = function( serverProps ){
					lookups.append( duplicate( arguments.serverProps ) );
					var key = arguments.serverProps.serverConfigFile ?: arguments.serverProps.directory;
					return structKeyExists( servers, key )
						? { serverIsNew : false, serverInfo : servers[ key ] }
						: { serverIsNew : true, serverInfo : { host : "127.0.0.1", port : 0, defaultBaseURL : "" } };
				} );
				serverService.$( method = "isServerRunning", callback = function( serverInfo ){
					return running[ arguments.serverInfo.name ?: "" ] ?: false;
				} );
				testServer = prepareMock( model( "TestServer" ) );
				testServer.$property( propertyName = "serverService", propertyScope = "variables", mock = serverService );
				testServer.$property( propertyName = "root", propertyScope = "variables", mock = "D:/projects/sample" );
				useSettings( "/tests/runner.cfm" );
			} );

			it( "uses a full URL as it is", function(){
				useSettings( "http://localhost:61000/tests/runner.cfm?opt=1" );
				expect( testServer.runnerUrl() ).toBe( "http://localhost:61000/tests/runner.cfm?opt=1" );
				expect( testServer.siteUrl() ).toBe( "http://localhost:61000/" );
				expect( lookups ).toBeEmpty();
			} );

			it( "joins a path to the base URL of the project's server", function(){
				addServer( "D:/projects/sample", { defaultBaseURL : "http://127.0.0.1:60310", port : 60310 } );
				expect( testServer.runnerUrl() ).toBe( "http://127.0.0.1:60310/tests/runner.cfm" );
				expect( testServer.siteUrl() ).toBe( "http://127.0.0.1:60310/" );
			} );

			it( "uses server.json when the project has one", function(){
				var root = createTempProject();
				try {
					fileWrite( root & "/server.json", "{}" );
					testServer.$property( propertyName = "root", propertyScope = "variables", mock = root );
					addServer( root & "/server.json", { defaultBaseURL : "http://127.0.0.1:60311", port : 60311 } );
					expect( testServer.runnerUrl() ).toBe( "http://127.0.0.1:60311/tests/runner.cfm" );
				} finally {
					deleteDirectory( root );
				}
			} );

			it( "builds the base URL from the host and port when CommandBox has none", function(){
				addServer( "D:/projects/sample", { host : "0.0.0.0", port : 8080, defaultBaseURL : "" } );
				expect( testServer.runnerUrl() ).toBe( "http://127.0.0.1:8080/tests/runner.cfm" );
			} );

			it( "uses HTTP when the server also has an HTTPS address", function(){
				addServer( "D:/projects/sample", { host : "localhost", port : 8080, defaultBaseURL : "https://localhost:8443" } );
				expect( testServer.siteUrl() ).toBe( "http://localhost:8080/" );

				addServer( "D:/projects/sample", { HTTPEnable : false, port : 0, defaultBaseURL : "https://localhost:8443" } );
				expect( testServer.siteUrl() ).toBe( "https://localhost:8443/" );
			} );

			it( "reads an engine's server from its server JSON file", function(){
				addServer( "D:/projects/sample/server-lucee@5.json", { defaultBaseURL : "http://127.0.0.1:60401", port : 60401 } );
				expect( testServer.runnerUrl( "server-lucee@5.json" ) ).toBe( "http://127.0.0.1:60401/tests/runner.cfm" );
				expect( lookups ).toBe( [ { serverConfigFile : "D:/projects/sample/server-lucee@5.json" } ] );
			} );

			it( "prefers a running engine when no engine is named", function(){
				useSettings(
					"/tests/runner.cfm",
					[ { name : "Lucee 5", configFile : "server-lucee@5.json" }, { name : "Adobe 2023", configFile : "server-adobe@2023.json" } ]
				);
				addServer( "D:/projects/sample/server-lucee@5.json", { name : "lucee", defaultBaseURL : "http://127.0.0.1:60401", port : 60401 } );
				addServer( "D:/projects/sample/server-adobe@2023.json", { name : "adobe", defaultBaseURL : "http://127.0.0.1:60402", port : 60402 } );
				expect( testServer.siteUrl() ).toBe( "http://127.0.0.1:60401/" );

				running.adobe = true;
				expect( testServer.siteUrl() ).toBe( "http://127.0.0.1:60402/" );
			} );

			it( "stops when the server has never started", function(){
				expect( function(){
					testServer.runnerUrl();
				} ).toThrow( type = "Release.Stop", regex = "no server has started for this project" );
				expect( function(){
					testServer.siteUrl( "server-lucee@5.json" );
				} ).toThrow( type = "Release.Stop", regex = "the server in server-lucee@5.json has not started" );
			} );

			it( "stops when CommandBox cannot read the server JSON file", function(){
				serverService.$( "resolveServerDetails" ).$throws( type = "JSONException", message = "Invalid JSON" );
				expect( function(){
					testServer.runnerUrl( "server-lucee@5.json" );
				} ).toThrow( type = "Release.Stop", regex = "could not read server-lucee@5.json: Invalid JSON" );
			} );
		} );
	}

	private void function useSettings( required string testRunner, array engines = [] ){
		testServer.$property(
			propertyName  = "settings",
			propertyScope = "variables",
			mock          = { testRunner : arguments.testRunner, engines : arguments.engines }
		);
	}

	/** Adds a server that the CommandBox stub knows, by its server JSON file or its folder. */
	private void function addServer( required string key, required struct serverInfo ){
		servers[ arguments.key ] = arguments.serverInfo;
	}
}
