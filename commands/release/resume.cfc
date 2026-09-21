/**
 * Finishes a release that stopped after the package was built or published.
 * .
 * It creates the tag when it does not exist yet, pushes the tag when origin does not have it,
 * and creates the GitHub Release from the zip file under .artifacts. It uses the version in
 * box.json.
 * .
 * {code:bash}
 * release resume
 * release resume --dryRun
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @dryRun Shows the commands without running them.
	 */
	function run( boolean dryRun = false ){
		var config = loadProject();
		var args   = arguments;
		guard( function(){
			service( "ReleaseService", config ).resume( dryRun = args.dryRun );
		} );
	}
}
