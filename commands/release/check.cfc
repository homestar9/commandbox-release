/**
 * Reports whether the current project is ready for a release.
 * .
 * It checks the module version, project settings, Git, changelog, required tools, and test
 * server. It lists the problems it finds and does not change project files.
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
