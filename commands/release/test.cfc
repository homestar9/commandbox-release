/**
 * Runs the project tests the way a release runs them.
 * .
 * If release.json lists engines, the command starts each engine, runs tests, and stops it
 * before starting the next one. It tries every engine even if one fails. With no engines, it
 * runs the tests once against the server at the test runner URL. That server must be running.
 * .
 * {code:bash}
 * release test
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	function run(){
		var config = loadProject();
		guard( function(){
			service( "TestRunner", config ).run();
		} );
	}
}
