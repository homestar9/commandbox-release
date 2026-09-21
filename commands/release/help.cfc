/**
 * Lists the available release commands. `release help` and `help release` show this text.
 */
component excludeFromHelp=true {

	function run(){
		print
			.line()
			.boldLine( "commandbox-release: release CFML modules and web apps with CommandBox" )
			.line()
			.line( "Run these commands from any folder inside a project that has box.json." )
			.line( "A module publishes to ForgeBox and GitHub. A web app publishes to GitHub only." )
			.line( "You choose during release init." )
			.line()
			.boldLine( "Fast flow (from the production branch)" )
			.line( "  release init                     set up a project once" )
			.line( "  release publish patch --dryRun   practice: nothing is written, published, or pushed" )
			.line( "  release publish patch            bump, commit, check, test, build, publish, tag" )
			.line( "                                   also: minor, major, prerelease, or minor beta" )
			.line()
			.boldLine( "Granular flow, and Gitflow or GitKraken" )
			.line( "  release bump patch               change the version and date the notes, no commit" )
			.line( "  (commit; with Gitflow, finish the release and check out the production branch)" )
			.line( "  release publish                  publish the version in box.json" )
			.line( "                                   a tag that already points here is used, not recreated" )
			.line()
			.boldLine( "Helpers" )
			.line( "  release check                    find problems that would stop a release" )
			.line( "  release test                     run the tests once, or on each configured engine" )
			.line( "  release package                  build and check the zip only" )
			.line( "  release notes                    show the release notes for the current version" )
			.line( "  release resume                   finish a release that stopped after publishing" )
			.line()
			.line( "Release settings are in release.json. Package exclusions are the box.json ignore list." )
			.line( "Update the module with:  box update commandbox-release --system" )
			.line()
			.line( "Show all help for one command: help release publish" )
			.line()
			.toConsole();
	}
}
