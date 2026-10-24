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
				expect( result.output ).notToInclude( "so this hotfix publishes" );
				expect( versionOn( "master" ) ).toBe( "1.0.1" );
				expect( versionOn( "develop" ) ).toBe( "1.0.1" );
				expect( git( [ "show", "develop:source.txt" ] ) ).toBe( "fixed" );
				expect( git( [ "branch", "--list", "hotfix/*" ] ) ).toBe( "" );
			} );

			it( "keeps the prerelease for a hotfix on a prerelease", function(){
				startPrereleaseHotfix();

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow on a prerelease hotfix" );

				expect( result.output ).toInclude( "box.json has prerelease 1.0.0-beta.2, so this hotfix publishes 1.0.0-beta.3." );
				expect( result.output ).toInclude( "To publish 1.0.0 instead, run: box release gitflow patch" );
				expect( versionOn( "master" ) ).toBe( "1.0.0-beta.3" );
				expect( versionOn( "develop" ) ).toBe( "1.0.0-beta.3" );
				expect( git( [ "log", "master", "--pretty=%s" ] ) ).toInclude( "Release 1.0.0-beta.3" );
				expect( fileExists( fixtureRoot & "/.artifacts/sample/1.0.0-beta.3/sample-1.0.0-beta.3.zip" ) ).toBeTrue();
			} );

			it( "finishes the prerelease when a hotfix uses patch", function(){
				startPrereleaseHotfix();

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow patch --skipTests" );
				expectCommand( result, "release gitflow patch on a prerelease hotfix" );

				expect( result.output ).notToInclude( "so this hotfix publishes" );
				expect( versionOn( "master" ) ).toBe( "1.0.0" );
				expect( versionOn( "develop" ) ).toBe( "1.0.0" );
			} );

			it( "publishes a prerelease hotfix that already has a newer version", function(){
				startPrereleaseHotfix();
				setVersion( "1.0.0-beta.3" );
				commitAll( "Release 1.0.0-beta.3" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow on a prerelease hotfix with a new version" );

				expect( result.output ).notToInclude( "so this hotfix publishes" );
				expect( versionOn( "master" ) ).toBe( "1.0.0-beta.3" );
				expect( git( [ "log", "master", "--pretty=%s" ] ) ).notToInclude( "1.0.0-beta.4" );
			} );

			it( "changes the prerelease label when a hotfix has preid and no level", function(){
				startPrereleaseHotfix();

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow preid=rc --skipTests" );
				expectCommand( result, "release gitflow with preid on a prerelease hotfix" );

				expect( versionOn( "master" ) ).toBe( "1.0.0-rc.1" );
			} );

			it( "shows the prerelease version in a practice run of a prerelease hotfix", function(){
				startPrereleaseHotfix();
				var branchesBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );
				var packageBefore  = fileRead( fixtureRoot & "/box.json" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --dryRun --skipTests" );
				expectCommand( result, "the practice run of a prerelease hotfix" );
				expect( result.output ).toInclude( "box release bump prerelease" );
				expect( result.output ).toInclude( "1.0.0-beta.2 -> 1.0.0-beta.3" );
				expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( branchesBefore );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
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

			it( "runs the test command on the release branch and does not repeat it on production", function(){
				writeTestTask( fixtureRoot, "tests/Fail.cfc", false );
				writeTestTask( fixtureRoot, "tests/Pass.cfc", true );
				writeSettings( { runTests : true, testCommand : "task run taskFile=tests/Fail.cfc" } );
				commitAll( "Use a failing test command" );
				var masterBefore  = git( [ "rev-parse", "master" ] );
				var developBefore = git( [ "rev-parse", "develop" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "1 fixture test failed." );
				expect( result.output ).toInclude( "The test command failed: box task run taskFile=tests/Fail.cfc (exit code 1)" );
				expect( result.output ).toInclude( "Nothing was merged or pushed" );
				expect( currentBranch() ).toBe( "release/1.1.0" );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
				expect( git( [ "rev-parse", "develop" ] ) ).toBe( developBefore );

				writeSettings( { runTests : true, testCommand : "task run taskFile=tests/Pass.cfc" } );
				commitAll( "Fix the tests" );
				var retry = fixtureProcess.runCommand( fixtureRoot, "release gitflow" );
				expectCommand( retry, "release gitflow with a passing test command" );
				expect( retry.output ).toInclude( "Fixture tests passed." );
				expect( retry.output ).toInclude( "The tests passed on release/1.1.0." );
				expect( retry.output ).toInclude( "This build does not run them again." );
				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( currentBranch() ).toBe( "develop" );
			} );

			it( "stops before pushing when the beforePublish command fails, and skips it with skipHooks", function(){
				writeTestTask( fixtureRoot, "tests/Fail.cfc", false );
				writeSettings( { hooks : { beforePublish : "task run taskFile=tests/Fail.cfc" } } );
				commitAll( "Use a failing beforePublish command" );
				var originMasterBefore = originCommit( "master" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "The beforePublish command failed: box task run taskFile=tests/Fail.cfc (exit code 1)" );
				expect( result.output ).toInclude( "is merged on this computer, and nothing was published or pushed" );
				expect( result.output ).notToInclude( "already ran" );
				expect( originCommit( "master" ) ).toBe( originMasterBefore );

				gitOk( [ "switch", "release/1.1.0" ] );
				var retry = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests --skipHooks" );
				expectCommand( retry, "release gitflow --skipHooks" );
				expect( retry.output ).toInclude( "The beforePublish command was skipped (requested with skipHooks)" );
				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( originCommit( "master" ) ).toBe( git( [ "rev-parse", "master" ] ) );
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

			it( "combines the changelog when it is the only conflict", function(){
				startChangelogConflict();

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow with a changelog conflict" );
				expect( result.output ).toInclude( "Combined CHANGELOG.md: kept the [Unreleased] notes on develop and added [1.0.1]." );
				expect( result.output ).notToInclude( "still lists these notes" );

				var developLog = git( [ "show", "develop:CHANGELOG.md" ] );
				var noteAt     = find( "- Develop note", developLog );
				var hotfixAt   = find( "[1.0.1]", developLog );
				var fixAt      = find( "- Fix the bug", developLog );
				var firstAt    = find( "[1.0.0]", developLog );
				expect( noteAt ).toBeGT( 0 );
				expect( hotfixAt ).toBeGT( noteAt );
				expect( fixAt ).toBeGT( hotfixAt );
				expect( firstAt ).toBeGT( fixAt );
				expect( changelogCount( "develop", "- Fix the bug" ) ).toBe( 1 );
				expect( changelogCount( "develop", "- Develop note" ) ).toBe( 1 );

				expect( parentCount( "develop" ) ).toBe( 2 );
				expect( git( [ "log", "-1", "--pretty=%B", "develop" ] ) ).notToInclude( "Conflicts" );
				expect( git( [ "show", "master:CHANGELOG.md" ] ) ).toInclude( "[1.0.1]" );
				expect( git( [ "show", "master:CHANGELOG.md" ] ) ).notToInclude( "Develop note" );
				expect( versionOn( "master" ) ).toBe( "1.0.1" );
				expect( versionOn( "develop" ) ).toBe( "1.0.1" );
				expect( originCommit( "master" ) ).toBe( git( [ "rev-parse", "master" ] ) );
				expect( originCommit( "develop" ) ).toBe( git( [ "rev-parse", "develop" ] ) );
				expect( git( [ "branch", "--list", "hotfix/*" ] ) ).toBe( "" );
				expect( git( [ "ls-remote", "--heads", "origin", "hotfix/1.0.1" ] ) ).toBe( "" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
				expect( currentBranch() ).toBe( "develop" );
			} );

			it( "combines a changelog with Windows line endings", function(){
				var crlf = chr( 13 ) & chr( 10 );
				gitOk( [ "config", "core.autocrlf", "false" ] );
				startChangelogConflict( "- Develop note", crlf );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow with a CRLF changelog" );

				// The command ends on develop, so the working file is develop's changelog.
				expect( currentBranch() ).toBe( "develop" );
				var content = fileRead( fixtureRoot & "/CHANGELOG.md" );
				expect( content ).toInclude( "- Develop note" & crlf );
				expect( content ).toInclude( "[1.0.1]" );
				expect( content ).toInclude( "- Fix the bug" & crlf );
				expect( replace( content, crlf, "", "all" ) ).notToInclude( chr( 10 ) );
			} );

			it( "warns when develop already lists a note that the hotfix released", function(){
				startChangelogConflict( "- Fix the bug" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow with a repeated note" );
				expect( result.output ).toInclude( "warning  develop still lists these notes under [Unreleased]" );
				expect( result.output ).toInclude( "- Fix the bug" );
				expect( changelogCount( "develop", "- Fix the bug" ) ).toBe( 2 );
			} );

			it( "keeps the combined changelog on a re-run after a later conflict", function(){
				startChangelogConflict();
				fileWrite( fixtureRoot & "/source.txt", "hotfix change" );
				commitAll( "Hotfix source change" );
				gitOk( [ "switch", "master" ] );
				fileWrite( fixtureRoot & "/source.txt", "master change" );
				commitAll( "Master source change" );
				gitOk( [ "switch", "hotfix/1.0.1" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Combined CHANGELOG.md" );
				expect( result.output ).toInclude( "could not be merged into master" );
				expect( parentCount( "develop" ) ).toBe( 2 );
				expect( currentBranch() ).toBe( "hotfix/1.0.1" );
				var developAfterFirstRun = git( [ "rev-parse", "develop" ] );

				// Resolve the production conflict by hand, as the instructions say.
				gitOk( [ "switch", "master" ] );
				fixtureProcess.runGit( fixtureRoot, [ "merge", "--no-ff", "hotfix/1.0.1" ] );
				fileWrite( fixtureRoot & "/source.txt", "resolved" );
				gitOk( [ "add", "source.txt" ] );
				gitOk( [ "commit", "-m", "Merge hotfix/1.0.1 into master" ] );
				gitOk( [ "switch", "hotfix/1.0.1" ] );

				var retry = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( retry, "release gitflow after fixing master" );
				expect( retry.output ).notToInclude( "Combined CHANGELOG.md" );
				expect( git( [ "rev-parse", "develop" ] ) ).toBe( developAfterFirstRun );
				expect( versionOn( "master" ) ).toBe( "1.0.1" );
				expect( originCommit( "develop" ) ).toBe( developAfterFirstRun );
			} );

			it( "cancels when the changelog changed on both branches", function(){
				// master and develop still have "- Pending change" under [Unreleased]. The hotfix
				// releases it while develop adds a note above it. Both edit the same lines, so
				// Git reports a conflict.
				gitOk( [ "switch", "-c", "hotfix/1.0.1", "master" ] );
				fileWrite( fixtureRoot & "/source.txt", "fixed" );
				commitAll( "Fix the bug" );
				gitOk( [ "switch", "develop" ] );
				writeChangelog( "- Develop note" & chr( 10 ) & "- Pending change" );
				commitAll( "Develop note" );
				gitOk( [ "switch", "hotfix/1.0.1" ] );
				var masterBefore  = git( [ "rev-parse", "master" ] );
				var developBefore = git( [ "rev-parse", "develop" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "could not be merged into develop" );
				expect( result.output ).toInclude( "The [Unreleased] notes in CHANGELOG.md changed on both branches." );
				expect( result.output ).toInclude( "git merge --no-ff hotfix/1.0.1" );
				expect( result.output ).notToInclude( "Combined CHANGELOG.md" );
				expect( currentBranch() ).toBe( "hotfix/1.0.1" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
				expect( git( [ "rev-parse", "develop" ] ) ).toBe( developBefore );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
				expect( originCommit( "master" ) ).toBe( masterBefore );
				expect( fileExists( fixtureRoot & "/.git/MERGE_HEAD" ) ).toBeFalse();
			} );

			it( "cancels when another file conflicts as well as the changelog", function(){
				startChangelogConflict();
				fileWrite( fixtureRoot & "/source.txt", "hotfix change" );
				commitAll( "Hotfix source change" );
				gitOk( [ "switch", "develop" ] );
				fileWrite( fixtureRoot & "/source.txt", "develop change" );
				commitAll( "Develop source change" );
				gitOk( [ "switch", "hotfix/1.0.1" ] );
				var developBefore = git( [ "rev-parse", "develop" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "could not be merged into develop" );
				expect( result.output ).toInclude( "These files have conflicts: CHANGELOG.md, source.txt" );
				expect( result.output ).notToInclude( "Combined CHANGELOG.md" );
				expect( currentBranch() ).toBe( "hotfix/1.0.1" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
				expect( git( [ "rev-parse", "develop" ] ) ).toBe( developBefore );
			} );

			it( "cancels a release branch merge when develop added notes after the branch started", function(){
				gitOk( [ "switch", "-c", "release/1.1.0" ] );
				gitOk( [ "switch", "develop" ] );
				writeChangelog( "- Develop note" & chr( 10 ) & "- Pending change" );
				commitAll( "Develop note" );
				gitOk( [ "switch", "release/1.1.0" ] );
				var masterBefore  = git( [ "rev-parse", "master" ] );
				var developBefore = git( [ "rev-parse", "develop" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "could not be merged into develop" );
				expect( result.output ).toInclude( "The [Unreleased] notes in CHANGELOG.md changed on both branches." );
				expect( currentBranch() ).toBe( "release/1.1.0" );
				expect( versionOn( "release/1.1.0" ) ).toBe( "1.1.0" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
				expect( git( [ "rev-parse", "develop" ] ) ).toBe( developBefore );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
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

			it( "pushes to the remote named in release.json", function(){
				gitOk( [ "remote", "rename", "origin", "upstream-test" ] );
				writeSettings( { remote : "upstream-test" } );
				commitAll( "Use another remote" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expectCommand( result, "release gitflow minor with another remote" );
				expect( result.output ).toInclude( "Pushed master and develop to upstream-test" );
				expect( originCommit( "master" ) ).toBe( git( [ "rev-parse", "master" ] ) );
				expect( originCommit( "develop" ) ).toBe( git( [ "rev-parse", "develop" ] ) );
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

	/**
	 * Writes the changelog with the given [Unreleased] notes. An empty value leaves the section
	 * empty, as it is after a release.
	 */
	private void function writeChangelog( string unreleased = "- Pending change", string lineEnding = chr( 10 ) ){
		var lf      = arguments.lineEnding;
		var heading = repeatString( chr( 35 ), 2 ) & " ";
		var notes   = len( arguments.unreleased ) ? replace( arguments.unreleased, chr( 10 ), lf, "all" ) & lf & lf : "";
		fileWrite(
			fixtureRoot & "/CHANGELOG.md",
			heading & "[Unreleased]" & lf & lf & notes
				& heading & "[1.0.0] - 2026-08-07" & lf & lf & "- First release" & lf
		);
	}

	/**
	 * Prepares the common hotfix conflict: an empty [Unreleased] on master and develop, a hotfix
	 * from master with a note, and a new note on develop. Leaves the hotfix branch checked out.
	 */
	private void function startChangelogConflict( string developNote = "- Develop note", string lineEnding = chr( 10 ) ){
		writeChangelog( "" );
		commitAll( "Release the pending change" );
		gitOk( [ "branch", "-f", "master", "develop" ] );
		gitOk( [ "switch", "-c", "hotfix/1.0.1", "master" ] );
		writeChangelog( "- Fix the bug" );
		commitAll( "Fix the bug" );
		gitOk( [ "switch", "develop" ] );
		writeChangelog( arguments.developNote, arguments.lineEnding );
		commitAll( "Develop note" );
		gitOk( [ "switch", "hotfix/1.0.1" ] );
	}

	/**
	 * Publishes 1.0.0-beta.2 on master and origin, then starts a hotfix from master with a fix.
	 * Leaves the hotfix branch checked out.
	 */
	private void function startPrereleaseHotfix(){
		setVersion( "1.0.0-beta.2" );
		commitAll( "Release 1.0.0-beta.2" );
		gitOk( [ "branch", "-f", "master", "develop" ] );
		gitOk( [ "push", "origin", "master", "develop" ] );
		expect( versionOn( "origin/master" ) ).toBe( "1.0.0-beta.2" );
		gitOk( [ "switch", "-c", "hotfix/1.0.0-beta.3", "master" ] );
		fileWrite( fixtureRoot & "/source.txt", "fixed" );
		commitAll( "Fix the bug" );
	}

	/** Returns the number of parents of a branch's last commit. */
	private numeric function parentCount( required string branch ){
		return listLen( git( [ "rev-list", "--parents", "-1", arguments.branch ] ), " " ) - 1;
	}

	/** Returns how many times a text appears in a branch's changelog. */
	private numeric function changelogCount( required string branch, required string text ){
		var content = git( [ "show", arguments.branch & ":CHANGELOG.md" ] );
		return ( len( content ) - len( replace( content, arguments.text, "", "all" ) ) ) / len( arguments.text );
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
