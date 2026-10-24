/**
 * Publishes a release.
 * .
 * With no level, this command publishes the version in box.json. It checks Git and updates
 * the production branch. Then it runs tests and builds and checks the zip. It publishes to
 * ForgeBox and GitHub when those services are enabled. It waits until the checks pass before
 * publishing, tagging, or pushing.
 * .
 * With a level such as patch, it changes the version and dates the [Unreleased] notes first.
 * It commits the changes as "Release x.y.z" and then publishes. Run this form from the
 * production branch.
 * .
 * If Gitflow or GitKraken already made the version tag at this commit, this command uses it.
 * It pushes the tag if the remote does not have it.
 * .
 * {code:bash}
 * release publish
 * release publish --dryRun
 * release publish patch
 * release publish minor beta
 * release publish --skipTests buildID=7
 * release publish --skipHooks
 * {code}
 * .
 * If release.json sets hooks.beforePublish, this command runs it after the build passes and
 * before it publishes or pushes anything.
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @level     Changes the version before publishing. Use major, minor, or patch for a normal
	 *            release. Use prerelease to update a prerelease. Use premajor, preminor, or
	 *            prepatch to start one. Use none to keep the version and date the changelog.
	 * @level.options major,minor,patch,prerelease,premajor,preminor,prepatch,none
	 * @preid     A prerelease label, such as beta. With major, minor, or patch, the label starts
	 *            a prerelease for that level.
	 * @dryRun    Checks and builds the release. It shows version, commit, publish, tag, and push
	 *            steps without running them.
	 * @skipTests Skips the tests. Use only when the current version was already tested.
	 * @buildID   An optional build ID added to the package. CI uses its run number.
	 * @skipHooks Skips the beforePublish command in release.json.
	 */
	function run(
		string level      = "",
		string preid      = "",
		boolean dryRun    = false,
		boolean skipTests = false,
		string buildID    = "",
		boolean skipHooks = false
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
					buildID   = args.buildID,
					skipHooks = args.skipHooks
				);
			} else {
				release.run(
					dryRun    = args.dryRun,
					skipTests = args.skipTests,
					buildID   = args.buildID,
					skipHooks = args.skipHooks
				);
			}
		} );
	}
}
