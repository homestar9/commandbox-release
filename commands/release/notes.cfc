/**
 * Prints the release notes from a version's changelog section.
 * .
 * {code:bash}
 * release notes
 * release notes 1.2.0
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @version The version to show. The default is the version in box.json.
	 */
	function run( string version = "" ){
		var config    = loadProject();
		var requested = arguments.version;
		guard( function(){
			service( "ReleaseService", config ).notes( requested );
		} );
	}
}
