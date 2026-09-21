/**
 * Finishes a release that stopped after building or publishing the package.
 * .
 * It reads the version from box.json. It creates a missing tag, pushes a local tag if needed,
 * and creates the GitHub Release from the zip in .artifacts.
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
