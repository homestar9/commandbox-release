/**
 * Merges a Gitflow release or hotfix branch and publishes the package.
 * .
 * On develop, this command creates a release branch, such as release/1.2.0. On a release or
 * hotfix branch, it uses the current branch.
 * .
 * It changes the version when needed and runs enabled tests on the release or hotfix branch.
 * Then it merges that branch into develop and the production branch. The production branch
 * holds published versions. The command publishes from that branch, pushes both branches,
 * and deletes the release or hotfix branch unless you use --keepBranch.
 * .
 * The merges happen on your computer. Nothing is pushed until the build passes. If a step
 * fails before publishing, fix the problem and run the command again on the release or hotfix
 * branch without a level. Follow any recovery steps printed by the command.
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
	 * @level      The version change, such as patch or minor. Leave it out to use the version
	 *             in box.json if that version is newer than production. Otherwise, a hotfix
	 *             uses patch, and other branches require a level. Use none to keep the version
	 *             and date the release notes.
	 * @level.options major,minor,patch,prerelease,premajor,preminor,prepatch,none
	 * @preid      A prerelease label, such as beta. With major, minor, or patch, the label
	 *             starts a version for testing before the normal release. For example, minor
	 *             with beta changes 1.0.0 to 1.1.0-beta.1.
	 * @dryRun     Shows the steps and builds the package from the current branch. It writes
	 *             build files but does not change branches, box.json, or the changelog. It does
	 *             not publish or push.
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
