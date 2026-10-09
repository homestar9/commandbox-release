/**
 * Runs `release gitflow` in temporary projects with master and develop branches.
 *
 * Each project uses a local Git repository as origin. ForgeBox and GitHub publishing are off.
 * The command creates and merges branches, changes the version, builds the package, and pushes
 * to that local repository.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "release gitflow", function(){
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

			it( "creates a release branch on develop, merges it, and pushes both branches", function(){
				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expectCommand( result, "release gitflow minor" );

				expect( currentBranch() ).toBe( "develop" );
				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( versionOn( "develop" ) ).toBe( "1.1.0" );
				expect( git( [ "log", "master", "--pretty=%s" ] ) ).toInclude( "Release 1.1.0" );
				expect( git( [ "log", "-1", "master", "--pretty=%s" ] ) ).toInclude( "Merge branch 'release/1.1.0'" );
				expect( git( [ "branch", "--list", "release/*" ] ) ).toBe( "" );
				expect( originCommit( "master" ) ).toBe( git( [ "rev-parse", "master" ] ) );
				expect( originCommit( "develop" ) ).toBe( git( [ "rev-parse", "develop" ] ) );
				expect( fileExists( fixtureRoot & "/.artifacts/sample/1.1.0/sample-1.1.0.zip" ) ).toBeTrue();
			} );

			it( "merges and builds a release branch that already has the new version", function(){
				gitOk( [ "switch", "-c", "release/1.1.0" ] );
				gitOk( [ "push", "-u", "origin", "release/1.1.0" ] );
				setVersion( "1.1.0" );
				commitAll( "Release 1.1.0" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow" );

				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( git( [ "branch", "--list", "release/*" ] ) ).toBe( "" );
				expect( git( [ "ls-remote", "--heads", "origin", "release/1.1.0" ] ) ).toBe( "" );
			} );

			it( "merges a hotfix, builds a patch version, and warns about an open release branch", function(){
				gitOk( [ "branch", "release/1.1.0", "develop" ] );
				gitOk( [ "switch", "-c", "hotfix/1.0.1", "master" ] );
				fileWrite( fixtureRoot & "/source.txt", "fixed" );
				commitAll( "Fix the bug" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow on a hotfix branch" );

				expect( result.output ).toInclude( "Release branch release/1.1.0 is open" );
				expect( versionOn( "master" ) ).toBe( "1.0.1" );
				expect( versionOn( "develop" ) ).toBe( "1.0.1" );
				expect( git( [ "show", "develop:source.txt" ] ) ).toBe( "fixed" );
				expect( git( [ "branch", "--list", "hotfix/*" ] ) ).toBe( "" );
			} );

			it( "asks for a level on develop when the version was already released", function(){
				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Choose a version level" );
				expect( git( [ "branch", "--list", "release/*" ] ) ).toBe( "" );
			} );

			it( "stops before creating a branch when the tag already exists", function(){
				gitOk( [ "tag", "v1.1.0", "master" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Tag v1.1.0 already exists" );
				expect( currentBranch() ).toBe( "develop" );
				expect( git( [ "branch", "--list", "release/*" ] ) ).toBe( "" );
			} );

			it( "stops before merging when tests fail and succeeds after tests are turned off", function(){
				// No server answers at the test runner URL, so the tests stop.
				writeSettings( { runTests : true, testRunner : "http://127.0.0.1:1/tests/runner.cfm" } );
				commitAll( "Enable tests" );
				var masterBefore  = git( [ "rev-parse", "master" ] );
				var developBefore = git( [ "rev-parse", "develop" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Nothing was merged or pushed" );
				expect( currentBranch() ).toBe( "release/1.1.0" );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
				expect( git( [ "rev-parse", "develop" ] ) ).toBe( developBefore );

				// Turn off tests on the release branch. The second run keeps version 1.1.0.
				writeSettings( { runTests : false } );
				commitAll( "Fix the test settings" );
				var retry = fixtureProcess.runCommand( fixtureRoot, "release gitflow" );
				expectCommand( retry, "release gitflow after a fix" );
				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( currentBranch() ).toBe( "develop" );
			} );

			it( "cancels a merge with conflicts and leaves production unchanged", function(){
				// develop and the hotfix change the same line.
				fileWrite( fixtureRoot & "/source.txt", "develop change" );
				commitAll( "Develop change" );
				gitOk( [ "switch", "-c", "hotfix/1.0.1", "master" ] );
				fileWrite( fixtureRoot & "/source.txt", "hotfix change" );
				commitAll( "Hotfix change" );
				var masterBefore = git( [ "rev-parse", "master" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "could not be merged into develop" );
				expect( currentBranch() ).toBe( "hotfix/1.0.1" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
				expect( originCommit( "master" ) ).toBe( masterBefore );
			} );

			it( "stops when develop and origin both have new commits", function(){
				var otherRoot = fixtureRoot & "-other";
				try {
					expectGit( fixtureProcess.runGit( getDirectoryFromPath( fixtureRoot ), [ "clone", "--branch", "develop", originRoot, otherRoot ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "config", "user.email", "tests@example.com" ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "config", "user.name", "Release Tests" ] ) );
					fileWrite( otherRoot & "/other.txt", "from origin" );
					expectGit( fixtureProcess.runGit( otherRoot, [ "add", "." ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "commit", "-m", "Upstream change" ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "push", "origin", "develop" ] ) );
				} finally {
					deleteDirectory( otherRoot );
				}
				fileWrite( fixtureRoot & "/local.txt", "local" );
				commitAll( "Local change" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "both have new commits" );
				expect( git( [ "branch", "--list", "release/*" ] ) ).toBe( "" );
			} );

			it( "shows the dry-run steps without changing branches, tags, or box.json", function(){
				var branchesBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );
				var packageBefore  = fileRead( fixtureRoot & "/box.json" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --dryRun --skipTests" );
				expectCommand( result, "the practice run" );
				expect( result.output ).toInclude( "git switch -c release/1.1.0 develop" );
				expect( result.output ).toInclude( "1.0.0 -> 1.1.0" );
				expect( result.output ).toInclude( "Practice run complete" );
				expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( branchesBefore );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
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
		writeChangelog();
		fileWrite( fixtureRoot & "/source.txt", "release fixture" );
		fileWrite( fixtureRoot & "/.gitignore", ".tmp/" & chr( 10 ) & ".artifacts/" & chr( 10 ) );

		originRoot = fixtureRoot & "-origin.git";
		gitOk( [ "init" ] );
		gitOk( [ "symbolic-ref", "HEAD", "refs/heads/master" ] );
		gitOk( [ "config", "user.email", "tests@example.com" ] );
		gitOk( [ "config", "user.name", "Release Tests" ] );
		commitAll( "Fixture" );
		directoryCreate( originRoot, true, true );
		expectGit( fixtureProcess.runGit( originRoot, [ "init", "--bare" ] ) );
		gitOk( [ "remote", "add", "origin", originRoot ] );
		gitOk( [ "push", "-u", "origin", "master" ] );
		gitOk( [ "switch", "-c", "develop" ] );
		gitOk( [ "push", "-u", "origin", "develop" ] );
	}

	private void function writeSettings( required struct overrides ){
		var settings = {
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

	private void function writeChangelog(){
		var lf      = chr( 10 );
		var heading = repeatString( chr( 35 ), 2 ) & " ";
		fileWrite(
			fixtureRoot & "/CHANGELOG.md",
			heading & "[Unreleased]" & lf & lf & "- Pending change" & lf & lf
				& heading & "[1.0.0] - 2026-08-07" & lf & lf & "- First release" & lf
		);
	}

	private void function setVersion( required string version ){
		var packageData = deserializeJSON( fileRead( fixtureRoot & "/box.json" ) );
		packageData.version = arguments.version;
		writeJSON( fixtureRoot & "/box.json", packageData );
	}

	private string function versionOn( required string branch ){
		return deserializeJSON( git( [ "show", arguments.branch & ":box.json" ] ) ).version;
	}

	private string function currentBranch(){
		return git( [ "rev-parse", "--abbrev-ref", "HEAD" ] );
	}

	private string function originCommit( required string branch ){
		return trim( fixtureProcess.runGit( originRoot, [ "rev-parse", arguments.branch ] ).output );
	}

	private void function commitAll( required string message ){
		gitOk( [ "add", "." ] );
		gitOk( [ "commit", "-m", arguments.message ] );
	}

	/** Runs Git in the temporary test project. Removes whitespace from the ends of its output. */
	private string function git( required array args ){
		return trim( fixtureProcess.runGit( fixtureRoot, arguments.args ).output );
	}

	private void function gitOk( required array args ){
		expectGit( fixtureProcess.runGit( fixtureRoot, arguments.args ) );
	}

	private void function expectGit( required struct result ){
		expectCommand( arguments.result, "Git" );
	}
}
