/**
 * Builds and checks the package zip file without publishing it.
 * .
 * It runs the tests and copies the shipped files into a temporary staging folder. Files
 * matched by the box.json ignore list stay out. It adds the version values, creates the zip
 * under .artifacts/<slug>/<version>/, checks the zip, and writes checksum files.
 * .
 * {code:bash}
 * release package
 * release package --skipTests
 * release package version=1.2.0 buildID=7
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @projectName The package folder and zip filename. The default is the box.json slug.
	 * @version     The version to build. The default is the version in box.json.
	 * @buildID     The build ID. The default is the short Git commit hash.
	 * @branch      The branch to build. The default is the current branch.
	 * @skipTests   Skips the tests and prints a warning.
	 */
	function run(
		string projectName = "",
		string version     = "",
		string buildID     = "",
		string branch      = "",
		boolean skipTests  = false
	){
		var config = loadProject();
		var args   = arguments;
		guard( function(){
			service( "PackageBuilder", config ).run( argumentCollection = args );
		} );
	}
}
