/**
 * Runs `release publish <level>` in temporary projects with a local Git remote.
 *
 * ForgeBox and GitHub publishing stay off in these fixtures, so nothing leaves this computer.
 * The flow still changes the version, commits, updates from origin, and builds the package.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "release publish <level>", function(){
			beforeEach( function(){
				fixtureProcess = new tests.support.FixtureProcess( repoRoot() );
				fixtureRoot    = fixtureProcess.createProject();
				originRoot     = "";
				writeProject();
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
				deleteDirectory( originRoot );
			} );

			it( "shows the version change and the commit without writing anything", function(){
				var packageBefore   = fileRead( fixtureRoot & "/box.json" );
				var changelogBefore = fileRead( fixtureRoot & "/CHANGELOG.md" );
				var commitsBefore   = commitCount();

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --dryRun --skipTests" );
				expectCommand( result, "the practice run" );
				expect( result.output ).toInclude( "1.0.0 -> 1.0.1" );
				expect( result.output ).toInclude( "git commit -m ""Release 1.0.1""" );
				expect( result.output ).toInclude( "Practice run complete" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( fileRead( fixtureRoot & "/CHANGELOG.md" ) ).toBe( changelogBefore );
				expect( commitCount() ).toBe( commitsBefore );
			} );

			it( "changes the version, commits it, and builds the package", function(){
				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expectCommand( result, "release publish patch" );

				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.0.1" );
				expect( fileRead( fixtureRoot & "/CHANGELOG.md" ) ).toInclude( versionHeading( "1.0.1" ) );
				expect( lastCommitMessage() ).toBe( "Release 1.0.1" );
				expect( fixtureProcess.runGit( fixtureRoot, [ "status", "--porcelain" ] ).output ).toBe( "" );
				expect( fileExists( fixtureRoot & "/.artifacts/sample/1.0.1/sample-1.0.1.zip" ) ).toBeTrue();
				expect( result.output ).toInclude( "Released v1.0.1" );
			} );

			it( "starts a prerelease when a label is given", function(){
				var result = fixtureProcess.runCommand( fixtureRoot, "release publish minor beta --skipTests" );
				expectCommand( result, "release publish minor beta" );
				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.1.0-beta.1" );
				expect( lastCommitMessage() ).toBe( "Release 1.1.0-beta.1" );
			} );

			it( "stops before changing files when [Unreleased] is empty", function(){
				writeChangelog( false );
				commitAll( "Empty notes" );
				var packageBefore = fileRead( fixtureRoot & "/box.json" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "empty" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( lastCommitMessage() ).toBe( "Empty notes" );
			} );

			it( "stops with Gitflow steps on a release branch", function(){
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "switch", "-c", "release/1.0.1" ] ) );
				var packageBefore = fileRead( fixtureRoot & "/box.json" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Gitflow" );
				expect( result.output ).toInclude( "box release bump patch" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( lastCommitMessage() ).toBe( "Fixture" );
			} );

			it( "stops on a branch that is not the production branch", function(){
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "switch", "-c", "feature/thing" ] ) );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "production branch master" );
				expect( lastCommitMessage() ).toBe( "Fixture" );
			} );

			it( "explains how to continue when the build fails after the commit", function(){
				// The tests are on, but nothing answers at the test runner URL, so the build stops.
				writeSettings( { runTests : true, testRunner : "http://127.0.0.1:1/tests/runner.cfm" } );
				commitAll( "Enable tests" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "committed locally" );
				expect( result.output ).toInclude( "box release publish" );
				expect( lastCommitMessage() ).toBe( "Release 1.0.1" );
				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.0.1" );
			} );
		} );
	}

	// FIXTURE HELPERS

	private void function writeProject(){
		fileWrite(
			fixtureRoot & "/box.json",
			'{"name":"Sample","slug":"sample","version":"1.0.0","type":"commandbox-modules","ignore":["/tests/"]}'
		);
		writeSettings( {} );
		writeChangelog( true );
		fileWrite( fixtureRoot & "/source.txt", "release fixture" );
		fileWrite( fixtureRoot & "/.gitignore", ".tmp/" & chr( 10 ) & ".artifacts/" & chr( 10 ) );
		createLocalGitRemote();
	}

	private void function writeSettings( required struct overrides ){
		var settings = {
			"projectType"      : "module",
			"branch"           : "master",
			"changelog"        : "CHANGELOG.md",
			"testRunner"       : "http://127.0.0.1:60299/tests/runner.cfm",
			"runTests"         : false,
			"gitSync"          : true,
			"requireCleanTree" : true,
			"publish"          : { "forgebox" : false, "github" : false },
			"engines"          : []
		};
		structAppend( settings, arguments.overrides, true );
		writeJSON( fixtureRoot & "/release.json", settings );
	}

	private void function writeChangelog( required boolean includeUnreleasedNote ){
		var lf      = chr( 10 );
		var heading = repeatString( chr( 35 ), 2 ) & " ";
		var content = heading & "[Unreleased]" & lf & lf;
		if ( arguments.includeUnreleasedNote ) {
			content &= "- Pending change" & lf & lf;
		}
		content &= heading & "[1.0.0] - 2026-08-07" & lf & lf & "- First release" & lf;
		fileWrite( fixtureRoot & "/CHANGELOG.md", content );
	}

	private void function createLocalGitRemote(){
		originRoot = fixtureRoot & "-origin.git";
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "init" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "symbolic-ref", "HEAD", "refs/heads/master" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "config", "user.email", "tests@example.com" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "config", "user.name", "Release Tests" ] ) );
		commitAll( "Fixture" );
		directoryCreate( originRoot, true, true );
		expectGit( fixtureProcess.runGit( originRoot, [ "init", "--bare" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "remote", "add", "origin", originRoot ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "push", "-u", "origin", "master" ] ) );
	}

	private void function commitAll( required string message ){
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "add", "." ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "commit", "-m", arguments.message ] ) );
	}

	private string function lastCommitMessage(){
		return trim( fixtureProcess.runGit( fixtureRoot, [ "log", "-1", "--pretty=%s" ] ).output );
	}

	private numeric function commitCount(){
		return val( trim( fixtureProcess.runGit( fixtureRoot, [ "rev-list", "--count", "HEAD" ] ).output ) );
	}

	private void function expectGit( required struct result ){
		expectCommand( arguments.result, "Git" );
	}
}
