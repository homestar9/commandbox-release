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
 * .
 * If release.json sets hooks.beforePublish, this command runs it after the production build
 * passes and before it publishes or pushes anything.
 * .
 * A Gitflow finish in GitKraken or git flow can tag a version, such as v1.0.1, before box.json
 * changes. On the production branch, this command shows the steps that fix it and asks whether
 * to do them. If you answer yes, it creates hotfix/1.0.1 (or release/1.1.0 for a minor
 * version), deletes the local tag, and publishes from that branch. Use --fixTag to do this
 * without the question, such as in a script.
 * .
 * {code:bash}
 * release gitflow --fixTag
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @level      The version change, such as patch or minor. Leave it out to use the version
	 *             in box.json if that version is newer than production. Otherwise, a hotfix
	 *             uses prerelease when box.json has a prerelease and patch for other versions.
	 *             Other branches require a level. Use patch to finish a prerelease. The command
	 *             asks first unless you use --finishPrerelease. Use none to keep the version
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
	 * @skipHooks  Skips the beforePublish command in release.json.
	 * @fixTag     On the production branch, fixes a Gitflow finish that tagged a version before
	 *             box.json changed, without asking.
	 * @finishPrerelease Lets a level finish a prerelease without asking, such as 1.0.0-beta.4
	 *             to 1.0.0. Without it, the command asks first. When nobody can answer, such
	 *             as in CI, it stops.
	 */
	function run(
		string level             = "",
		string preid             = "",
		boolean dryRun           = false,
		boolean skipTests        = false,
		boolean keepBranch       = false,
		boolean skipHooks        = false,
		boolean fixTag           = false,
		boolean finishPrerelease = false
	){
		var config  = loadProject();
		var args    = arguments;
		var confirm = confirmFunction();
		guard( function(){
			try {
				service( "GitflowService", config ).run( argumentCollection = args, confirm = confirm );
			} catch ( "Release.FinishedWithoutVersion" exception ) {
				if ( args.fixTag || !shouldFixTag( config, args ) ) {
					rethrow;
				}
				var fixArgs    = duplicate( args );
				fixArgs.fixTag = true;
				service( "GitflowService", config ).run( argumentCollection = fixArgs );
			}
		} );
	}
}
