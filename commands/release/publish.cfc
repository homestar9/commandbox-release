/**
 * Publishes a release.
 * .
 * Without a level, it publishes the version that is already in box.json. It checks the
 * repository, updates the production branch, runs the tests, builds and checks the zip file,
 * publishes to ForgeBox when enabled, and then creates the Git tag and GitHub Release when
 * enabled. Nothing is published, tagged, or pushed until every check passes.
 * .
 * With a level, it first changes the version, moves the [Unreleased] notes into a dated
 * section, and commits "Release x.y.z". It then runs the same publish steps. Run it from the
 * production branch.
 * .
 * When a tag for the version already points to the current commit, such as a tag created by
 * Gitflow or GitKraken, the command uses that tag and pushes it when origin does not have it.
 * .
 * {code:bash}
 * release publish
 * release publish --dryRun
 * release publish patch
 * release publish minor beta
 * release publish --skipTests buildID=7
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @level     Changes the version before publishing. major, minor, and patch change a normal
	 *            version. prerelease updates an active prerelease. premajor, preminor, and
	 *            prepatch start a prerelease. none keeps the version and only dates the changelog.
	 * @level.options major,minor,patch,prerelease,premajor,preminor,prepatch,none
	 * @preid     The prerelease label, such as beta. With major, minor, or patch, it starts a
	 *            prerelease of that level.
	 * @dryRun    Performs all safe steps. It prints but does not run the change, commit, publish,
	 *            tag, or push steps.
	 * @skipTests Skips the tests. Use only when the current version was already tested.
	 * @buildID   An optional build ID added to the package. CI uses its run number.
	 */
	function run(
		string level      = "",
		string preid      = "",
		boolean dryRun    = false,
		boolean skipTests = false,
		string buildID    = ""
	){
		var config = loadProject();
		var args   = arguments;
		guard( function(){
			var release = service( "ReleaseService", config );
			if ( len( trim( args.level ) ) ) {
				release.release(
					level     = args.level,
					preid     = args.preid,
					dryRun    = args.dryRun,
					skipTests = args.skipTests,
					buildID   = args.buildID
				);
			} else {
				release.run(
					dryRun    = args.dryRun,
					skipTests = args.skipTests,
					buildID   = args.buildID
				);
			}
		} );
	}
}
