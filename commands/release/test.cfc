/**
 * Runs the project tests the way a release runs them.
 * .
 * With engines listed in release.json, the command starts, tests, and stops one engine at a
 * time. A failed engine does not stop the remaining engines. Without engines, it runs the
 * tests once against the test runner URL, which must already be answering.
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
