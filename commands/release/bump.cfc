/**
 * Changes the version in box.json. It moves the [Unreleased] notes into a dated section for
 * that version. It does not commit, tag, or publish anything.
 * .
 * Use this command when you want to review or commit the version change yourself, or when
 * Gitflow will create the tag. Run `release publish` afterwards. To do everything in one
 * command, run `release publish patch` instead.
 * .
 * {code:bash}
 * release bump patch
 * release bump minor --dryRun
 * release bump preminor beta
 * release bump prerelease
 * release bump none
 * {code}
 */
component extends="commandbox-release.models.BaseCommand" {

	/**
	 * @level  The type of version change. major, minor, and patch change a normal version.
	 *         prerelease updates an active prerelease. premajor, preminor, and prepatch start a
	 *         prerelease. none keeps the version and only dates the changelog.
	 * @level.options major,minor,patch,prerelease,premajor,preminor,prepatch,none
	 * @preid  The prerelease label, such as beta or alpha. A new prerelease uses beta by default.
	 * @dryRun Shows the changes without writing any files.
	 * @allowPrereleaseRetarget Allows preminor to change the target of an active prerelease.
	 */
	function run(
		string level = "patch",
		string preid = "",
		boolean dryRun = false,
		boolean allowPrereleaseRetarget = false
	){
		var config = loadProject();
		var args   = arguments;
		guard( function(){
			service( "VersionBumper", config ).run( argumentCollection = args );
		} );
	}
}
