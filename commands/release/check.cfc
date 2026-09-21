/**
 * Reports whether the current project is ready for a release.
 * .
 * It checks the installed module, project settings, Git repository, changelog, required
 * tools, and test server. It lists every problem that it finds. It does not change anything.
 * .
 * {code:bash}
 * release check
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	function run(){
		var root = projectRoot();
		guard( function(){
			service( "ReadinessCheck" ).run( root );
		} );
	}
}
