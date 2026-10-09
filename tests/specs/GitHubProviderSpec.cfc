/** Checks GitHub repository names, release arguments, and SSH key advice. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "GitHubProvider", function(){
			beforeEach( function(){
				processRunner = model( "ProcessRunner" );
				fixtureRoot   = createTempProject();
				gitOk( [ "init" ] );
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
			} );

			it( "reads OWNER/REPO from GitHub remote URLs", function(){
				var provider = providerFor( "origin" );
				for (
					var remoteUrl in [
						"https://github.com/owner/repo.git",
						"https://github.com/owner/repo",
						"https://user@github.com/owner/repo.git",
						"git@github.com:owner/repo.git",
						"git@github.com:owner/repo",
						"ssh://git@github.com/owner/repo.git"
					]
				) {
					expect( provider.repoFromUrl( remoteUrl ) ).toBe( "owner/repo", remoteUrl );
				}
				expect( provider.repoFromUrl( "git@github.com:owner/my.repo.git" ) ).toBe( "owner/my.repo" );
				expect( provider.repoFromUrl( "https://gitlab.com/owner/repo.git" ) ).toBe( "" );
				expect( provider.repoFromUrl( "D:/work/repo-origin.git" ) ).toBe( "" );
				expect( provider.repoFromUrl( "" ) ).toBe( "" );
			} );

			it( "names the repository of the release remote in the release arguments", function(){
				gitOk( [ "remote", "add", "origin", "D:/work/fork.git" ] );
				gitOk( [ "remote", "add", "upstream", "git@github.com:owner/repo.git" ] );

				var args = providerFor( "upstream" ).releaseArgs(
					tagName    = "v1.1.0-beta.1",
					notesFile  = "notes.md",
					assets     = [ "pkg.zip", "pkg.zip.sha512" ],
					prerelease = true
				);
				expect( arrayToList( args, " " ) ).toBe(
					"release create v1.1.0-beta.1 --title v1.1.0-beta.1 --notes-file notes.md --prerelease --repo owner/repo pkg.zip pkg.zip.sha512"
				);
			} );

			it( "leaves out --repo when the release remote is not on github.com", function(){
				gitOk( [ "remote", "add", "origin", "D:/work/repo-origin.git" ] );

				var args = providerFor( "origin" ).releaseArgs( tagName = "v1.0.0", notesFile = "notes.md", assets = [ "pkg.zip" ] );
				expect( arrayToList( args, " " ) ).toBe( "release create v1.0.0 --title v1.0.0 --notes-file notes.md pkg.zip" );
			} );

			it( "gives SSH key advice only when the remote rejects the key", function(){
				var provider = providerFor( "origin" );
				var help     = provider.remoteHelp( "upstream", "git@github.com: Permission denied (publickey)." );
				expect( arrayToList( help, " " ) ).toInclude( "https://github.com/settings/ssh/new" );
				expect( arrayToList( help, " " ) ).toInclude( "git remote set-url upstream" );
				expect( provider.remoteHelp( "upstream", "fatal: repository not found" ) ).toBeEmpty();
			} );
		} );
	}

	/** Returns a provider for the fixture project. release.json names the release remote. */
	private any function providerFor( required string remote ){
		writeJSON( fixtureRoot & "/box.json", { "name" : "Sample", "slug" : "sample", "version" : "1.0.0" } );
		writeJSON( fixtureRoot & "/release.json", { "remote" : arguments.remote } );
		var config = model( "ProjectConfig" ).load( fixtureRoot );
		return model( "GitHubProvider" ).forProject( config );
	}

	private void function gitOk( required array args ){
		expectCommand( processRunner.run( "git", arguments.args, fixtureRoot ), "git " & arrayToList( arguments.args, " " ) );
	}
}
