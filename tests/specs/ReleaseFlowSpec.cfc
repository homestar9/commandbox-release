/**
 * Runs `release publish <level>` in temporary projects with a local Git remote.
 *
 * These test projects turn off ForgeBox and GitHub publishing. The command still changes the
 * version, commits, gets updates from a local origin, and builds the package.
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

			it( "shows version and commit steps without changing box.json or the changelog", function(){
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
				expect( result.output ).toInclude( "box release gitflow patch" );
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

			it( "stops before changing files when the new version's tag already exists", function(){
				// v1.0.1 is on an earlier commit, so publish patch would need it again.
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "v1.0.1" ] ) );
				fileWrite( fixtureRoot & "/source.txt", "second" );
				commitAll( "Second" );
				var packageBefore   = fileRead( fixtureRoot & "/box.json" );
				var changelogBefore = fileRead( fixtureRoot & "/CHANGELOG.md" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Tag v1.0.1 already exists" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( fileRead( fixtureRoot & "/CHANGELOG.md" ) ).toBe( changelogBefore );
				expect( lastCommitMessage() ).toBe( "Second" );
			} );

			it( "stops publish none before the commit when the current version was released", function(){
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "v1.0.0" ] ) );
				fileWrite( fixtureRoot & "/source.txt", "second" );
				commitAll( "Second" );
				var changelogBefore = fileRead( fixtureRoot & "/CHANGELOG.md" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish none --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Tag v1.0.0 already exists" );
				expect( fileRead( fixtureRoot & "/CHANGELOG.md" ) ).toBe( changelogBefore );
				expect( lastCommitMessage() ).toBe( "Second" );
			} );

			it( "explains how to finish a version that a Gitflow finish tagged without changing box.json", function(){
				// GitKraken finished hotfix/1.0.1 and tagged it, but box.json still has 1.0.0.
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "-a", "v1.0.1", "-m", "v1.0.1" ] ) );

				for ( var commandLine in [ "release publish --skipTests", "release publish patch --skipTests", "release gitflow" ] ) {
					var result = fixtureProcess.runCommand( fixtureRoot, commandLine );
					expect( result.exitCode ).notToBe( 0, commandLine );
					expect( result.output ).toInclude( "Tag v1.0.1 is on this commit, but box.json still has version 1.0.0" );
					expect( result.output ).toInclude( "git tag -d v1.0.1" );
					expect( result.output ).toInclude( "git switch -c hotfix/1.0.1" );
					expect( result.output ).toInclude( "box release gitflow patch" );
				}
				expect( lastCommitMessage() ).toBe( "Fixture" );
				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.0.0" );
			} );

			it( "names the level for a tagged minor version", function(){
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "v1.1.0" ] ) );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "git switch -c release/1.1.0" );
				expect( result.output ).toInclude( "box release gitflow minor" );
			} );

			it( "does not suggest deleting a tag that is already on the remote", function(){
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "-a", "v1.0.1", "-m", "v1.0.1" ] ) );
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "push", "origin", "v1.0.1" ] ) );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).notToInclude( "git tag -d" );
				expect( result.output ).toInclude( "Tag v1.0.1 already exists" );
				expect( lastCommitMessage() ).toBe( "Fixture" );
			} );

			it( "stops publish when the pull brings in new commits", function(){
				// Another clone pushes a commit, so origin is ahead of this checkout.
				var otherRoot = fixtureRoot & "-other";
				try {
					expectGit( fixtureProcess.runGit( getDirectoryFromPath( fixtureRoot ), [ "clone", "--branch", "master", originRoot, otherRoot ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "config", "user.email", "tests@example.com" ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "config", "user.name", "Release Tests" ] ) );
					fileWrite( otherRoot & "/source.txt", "changed on origin" );
					expectGit( fixtureProcess.runGit( otherRoot, [ "commit", "-am", "Upstream change" ] ) );
					expectGit( fixtureProcess.runGit( otherRoot, [ "push", "origin", "master" ] ) );
				} finally {
					deleteDirectory( otherRoot );
				}

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "The origin remote had new commits" );
				expect( lastCommitMessage() ).toBe( "Upstream change" );
				expect( fixtureProcess.runGit( fixtureRoot, [ "tag", "--list" ] ).output ).toBe( "" );
			} );

			it( "gets updates from the remote named in release.json", function(){
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "remote", "rename", "origin", "upstream-test" ] ) );
				writeSettings( { remote : "upstream-test" } );
				commitAll( "Use another remote" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expectCommand( result, "release publish patch with another remote" );
				expect( result.output ).toInclude( "Up to date with upstream-test/master" );
				expect( lastCommitMessage() ).toBe( "Release 1.0.1" );
			} );

			it( "stops before changing files when the remote does not exist", function(){
				writeSettings( { remote : "missing" } );
				commitAll( "Use a missing remote" );
				var packageBefore = fileRead( fixtureRoot & "/box.json" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Git has no remote named missing" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( lastCommitMessage() ).toBe( "Use a missing remote" );
			} );

			it( "stops the build when the test command fails and skips the command with skipTests", function(){
				writeTestTask( fixtureRoot, "tests/Fail.cfc", false );
				writeSettings( { runTests : true, testCommand : "task run taskFile=tests/Fail.cfc" } );
				commitAll( "Use a failing test command" );

				var practice = fixtureProcess.runCommand( fixtureRoot, "release publish patch --dryRun" );
				expect( practice.exitCode ).notToBe( 0 );
				expect( practice.output ).toInclude( "Running the tests with: box task run taskFile=tests/Fail.cfc" );
				expect( practice.output ).toInclude( "1 fixture test failed." );
				expect( practice.output ).toInclude( "The test command failed: box task run taskFile=tests/Fail.cfc (exit code 1)" );
				expect( practice.output ).notToInclude( "Practice run complete" );

				var skipped = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expectCommand( skipped, "release publish patch --skipTests with a failing test command" );
				expect( skipped.output ).notToInclude( "Running the tests with" );
				expect( skipped.output ).toInclude( "skipped the tests" );
				expect( lastCommitMessage() ).toBe( "Release 1.0.1" );
			} );

			it( "runs the beforePublish command after the build and before publishing", function(){
				writeTestTask( fixtureRoot, "tests/Pass.cfc", true );
				writeSettings( { hooks : { beforePublish : "box task run taskFile=tests/Pass.cfc" } } );
				commitAll( "Use a beforePublish command" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expectCommand( result, "release publish patch with a beforePublish command" );
				var hookAt = find( "Running: box task run taskFile=tests/Pass.cfc", result.output );
				expect( hookAt ).toBeGT( find( "Build complete", result.output ) );
				expect( find( "Released v1.0.1", result.output ) ).toBeGT( hookAt );
				expect( result.output ).toInclude( "Fixture tests passed." );
				expect( result.output ).toInclude( "The beforePublish command finished." );
			} );

			it( "only shows the beforePublish command in a practice run", function(){
				writeTestTask( fixtureRoot, "tests/Fail.cfc", false );
				writeSettings( { hooks : { beforePublish : "task run taskFile=tests/Fail.cfc" } } );
				commitAll( "Use a failing beforePublish command" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --dryRun --skipTests" );
				expectCommand( result, "the practice run with a beforePublish command" );
				expect( result.output ).toInclude( "This beforePublish command would run next" );
				expect( result.output ).toInclude( "box task run taskFile=tests/Fail.cfc" );
				expect( result.output ).notToInclude( "1 fixture test failed." );
			} );

			it( "stops when the beforePublish command fails, and skips it with skipHooks", function(){
				writeTestTask( fixtureRoot, "tests/Fail.cfc", false );
				writeSettings( { hooks : { beforePublish : "task run taskFile=tests/Fail.cfc" } } );
				commitAll( "Use a failing beforePublish command" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish patch --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "1 fixture test failed." );
				expect( result.output ).toInclude( "The beforePublish command failed: box task run taskFile=tests/Fail.cfc (exit code 1)" );
				expect( result.output ).toInclude( "Version 1.0.1 is committed locally and nothing was published" );
				expect( result.output ).notToInclude( "already ran" );
				expect( result.output ).notToInclude( "Released v1.0.1" );

				var skipped = fixtureProcess.runCommand( fixtureRoot, "release publish --skipTests --skipHooks" );
				expectCommand( skipped, "release publish --skipHooks" );
				expect( skipped.output ).toInclude( "The beforePublish command was skipped (requested with skipHooks)" );
				expect( skipped.output ).toInclude( "Released v1.0.1" );
			} );

			it( "explains how to continue when the build fails after the commit", function(){
				// No server answers at the test runner URL, so the build stops.
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
