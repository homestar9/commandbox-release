/**
 * Finds the URLs of the project's test server.
 *
 * release.json testRunner is a full URL or a path, such as "/tests/runner.cfm". A full URL is
 * used as it is. A path is joined to the base URL of the project's CommandBox server, so
 * release.json does not repeat the port. This component reads that URL from CommandBox each
 * time it is needed, because CommandBox can give a server a new port each time it starts.
 *
 * Run every CommandBox server lookup through this component.
 */
component extends="commandbox-release.models.BaseService" {

	property name="serverService" inject="serverService";

	/**
	 * Returns the full test runner URL.
	 *
	 * @configFile The server JSON file of an engine, such as "server-lucee@5.json". When it is
	 *             empty, the server in server.json is used, or the first listed engine that is
	 *             running.
	 */
	string function runnerUrl( string configFile = "" ){
		var runner = variables.settings.testRunner;
		if ( isFullUrl( runner ) ) {
			return runner;
		}
		return baseUrl( findServer( arguments.configFile ) ) & runner;
	}

	/**
	 * Returns the root URL of the test site, such as "http://127.0.0.1:60310/". Probes use it
	 * because requesting the runner URL would start all tests.
	 *
	 * @configFile The server JSON file of an engine. See runnerUrl().
	 */
	string function siteUrl( string configFile = "" ){
		var runner = variables.settings.testRunner;
		if ( isFullUrl( runner ) ) {
			return reReplaceNoCase( runner, "^(https?://[^/]+).*$", "\1" ) & "/";
		}
		return baseUrl( findServer( arguments.configFile ) ) & "/";
	}

	private boolean function isFullUrl( required string runner ){
		return reFindNoCase( "^https?://", arguments.runner ) > 0;
	}

	/**
	 * Returns the CommandBox server info for the test server. With a config file, it returns
	 * that file's server. Otherwise, it prefers a running server: the server in the project root
	 * when no engines are listed, or the first listed engine that is running. When none is
	 * running, it returns the first one that has a port, so the probe reports where it looked.
	 * It stops when no server has a port, because the server has never started.
	 */
	private struct function findServer( required string configFile ){
		var candidates = [];
		if ( len( arguments.configFile ) ) {
			candidates.append( arguments.configFile );
		} else if ( arrayLen( variables.settings.engines ) ) {
			for ( var engine in variables.settings.engines ) {
				candidates.append( engine.configFile );
			}
		} else {
			candidates.append( "" );
		}

		var fallback = {};
		for ( var candidate in candidates ) {
			var serverInfo = lookUp( candidate );
			if ( !len( baseUrl( serverInfo ) ) ) {
				continue;
			}
			if ( variables.serverService.isServerRunning( serverInfo ) ) {
				return serverInfo;
			}
			if ( structIsEmpty( fallback ) ) {
				fallback = serverInfo;
			}
		}
		if ( !structIsEmpty( fallback ) ) {
			return fallback;
		}

		var where = len( arguments.configFile ) ? "the server in #arguments.configFile# has not started"
			: arrayLen( variables.settings.engines ) ? "no listed engine has started"
			: "no server has started for this project";
		return stop(
			"testRunner is the path #variables.settings.testRunner#, but #where#. "
			& "Start one with ""box server start"", or set testRunner to a full URL."
		);
	}

	/**
	 * Returns CommandBox's server info for one server JSON file, or for the project root when
	 * the name is empty. It returns an empty struct for a server that CommandBox does not know.
	 */
	private struct function lookUp( required string configFile ){
		var serverProps = {};
		if ( len( arguments.configFile ) ) {
			serverProps.serverConfigFile = variables.root & "/" & arguments.configFile;
		} else if ( fileExists( variables.root & "/server.json" ) ) {
			serverProps.serverConfigFile = variables.root & "/server.json";
		} else {
			serverProps.directory = variables.root;
		}
		var details = {};
		try {
			details = variables.serverService.resolveServerDetails( serverProps );
		} catch ( any exception ) {
			return stop( "CommandBox could not read #len( arguments.configFile ) ? arguments.configFile : "the project's server"#: #exception.message#" );
		}
		return details.serverIsNew ? {} : details.serverInfo;
	}

	/**
	 * Returns the server's base URL without a trailing slash, or an empty string when the server
	 * has no port yet. It uses the URL that `box server open` uses. It uses HTTP when the server
	 * also listens on HTTP, because a self-signed certificate would stop the tests.
	 */
	private string function baseUrl( required struct serverInfo ){
		var info    = arguments.serverInfo;
		var host    = ( info.host ?: "" ) == "0.0.0.0" || !len( info.host ?: "" ) ? "127.0.0.1" : info.host;
		var port    = val( info.port ?: 0 );
		var httpUrl = ( info.HTTPEnable ?: true ) && port > 0 ? "http://#host#:#port#" : "";
		var base    = reReplace( info.defaultBaseURL ?: "", "/+$", "" );

		if ( len( base ) ) {
			return reFindNoCase( "^https://", base ) && len( httpUrl ) ? httpUrl : base;
		}
		if ( len( httpUrl ) ) {
			return httpUrl;
		}
		if ( ( info.SSLEnable ?: false ) && val( info.SSLPort ?: 0 ) > 0 ) {
			return "https://#host#:#val( info.SSLPort )#";
		}
		return "";
	}
}
