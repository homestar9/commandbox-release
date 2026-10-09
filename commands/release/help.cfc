/**
 * Lists the available release commands. `release help` and `help release` show this text.
 */
component excludeFromHelp=true {

	function run(){
		print
			.line()
			.boldLine( "commandbox-release: publish CFML modules and web apps" )
			.line()
			.line( "Run these commands from any folder inside a project that has box.json." )
			.line( "Modules use ForgeBox and GitHub. Web apps use GitHub by default." )
			.line( "Choose the project type when you run release init." )
			.line()
			.boldLine( "Change the version and publish from the production branch" )
			.line( "  release init                     set up a project once" )
			.line( "  release publish patch --dryRun   build the zip without changing the version" )
			.line( "  release publish patch            change the version, commit, and publish" )
			.line( "                                   use minor, major, or minor beta as needed" )
			.line()
			.boldLine( "Gitflow: merge and publish in one command" )
			.line( "  release gitflow minor            on develop: create release/x.y.z and finish it" )
			.line( "  release gitflow                  on a release or hotfix branch: finish it" )
			.line( "                                   merges into develop and production, then publishes" )
			.line()
			.boldLine( "Change the version and publish in separate steps" )
			.line( "  release bump patch               change the version and date the release notes" )
			.line( "  Commit the change. For Gitflow, finish the release and switch to production." )
			.line( "  release publish                  publish the version in box.json" )
			.line( "                                   uses an existing tag at the current commit" )
			.line()
			.boldLine( "Helpers" )
			.line( "  release check                    find problems that would stop a release" )
			.line( "  release test                     run the tests once, or on each configured engine" )
			.line( "  release package                  build and check the zip only" )
			.line( "  release notes                    show the release notes for the current version" )
			.line( "  release resume                   finish a release that stopped after publishing" )
			.line()
			.line( "Edit release.json for release settings and box.json to exclude package files." )
			.line( "Update the module with:  box update commandbox-release --system" )
			.line()
			.line( "Show all help for one command: help release publish" )
			.line()
			.toConsole();
	}
}
