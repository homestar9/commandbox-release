/**
 * Finishes a Gitflow release or hotfix and publishes it.
 * .
 * On develop, this command creates a release branch, such as release/1.2.0, and then finishes
 * it. On a release or hotfix branch, it finishes that branch.
 * .
 * To finish, it changes the version when needed and runs the tests on the branch. Then it
 * merges the branch into develop and the production branch, and publishes from the production
 * branch. Last, it pushes both branches and deletes the release branch.
 * .
 * The merges happen on your computer. Nothing is pushed until the build passes. If a step
 * fails before publishing, fix the problem and run the command again on the release branch.
 * .
 * {code:bash}
 * release gitflow minor
 * release gitflow minor --dryRun
 * release gitflow
 * release gitflow --keepBranch
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @level      The version change. Required on develop. On a hotfix branch, patch is the
	 *             default. Leave it out when the branch already has the new version.
	 * @level.options major,minor,patch,prerelease,premajor,preminor,prepatch,none
	 * @preid      A prerelease label, such as beta. With major, minor, or patch, the label
	 *             starts a prerelease for that level.
	 * @dryRun     Shows the steps and builds the package. It does not change branches or files,
	 *             publish, or push.
	 * @skipTests  Skips the tests. Use only when this version was already tested.
	 * @keepBranch Keeps the release or hotfix branch after the release.
	 */
	function run(
		string level       = "",
		string preid       = "",
		boolean dryRun     = false,
		boolean skipTests  = false,
		boolean keepBranch = false
	){
		var config = loadProject();
		var args   = arguments;
		guard( function(){
			service( "GitflowService", config ).run( argumentCollection = args );
		} );
	}
}
