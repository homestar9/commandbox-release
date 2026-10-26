/**
 * Runs `release gitflow` in temporary projects with master and develop branches.
 *
 * Each project uses a local Git repository as origin. ForgeBox and GitHub publishing are off.
 * The command creates and merges branches, changes the version, builds the package, and pushes
 * to that local repository.
 */
component extends="tests.support.BaseSpec" {

	function beforeAll(){
		fixtureProcess = new tests.support.FixtureProcess( repoRoot() ).start();
	}

	function afterAll(){
		fixtureProcess.stop();
	}

	function run(){
		describe( "release gitflow", function(){
			beforeEach( function(){
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

			it( "keeps develop's new notes when the hotfix releases notes that develop also has", function(){
				// master and develop still have "- Pending change" under [Unreleased]. The hotfix
				// releases it while develop adds a note above it. Both edit the same lines.
				gitOk( [ "switch", "-c", "hotfix/1.0.1", "master" ] );
				fileWrite( fixtureRoot & "/source.txt", "fixed" );
				commitAll( "Fix the bug" );
				gitOk( [ "switch", "develop" ] );
				writeChangelog( "- Develop note" & chr( 10 ) & "- Pending change" );
				commitAll( "Develop note" );
				gitOk( [ "switch", "hotfix/1.0.1" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expectCommand( result, "release gitflow with notes that develop also has" );
				expect( result.output ).toInclude( "Combined CHANGELOG.md: kept the [Unreleased] notes on develop, removed 1 note that [1.0.1] released, and added [1.0.1]." );
				expectReleasedOnDevelop( "1.0.1", "- Pending change", "- Develop note" );
				expect( versionOn( "master" ) ).toBe( "1.0.1" );
				expect( git( [ "show", "master:CHANGELOG.md" ] ) ).notToInclude( "Develop note" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
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

			it( "keeps develop's new notes when develop added notes after the release branch started", function(){
				gitOk( [ "switch", "-c", "release/1.1.0" ] );
				gitOk( [ "switch", "develop" ] );
				writeChangelog( "- Develop note" & chr( 10 ) & "- Pending change" );
				commitAll( "Develop note" );
				gitOk( [ "switch", "release/1.1.0" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expectCommand( result, "release gitflow minor with new notes on develop" );
				expectReleasedOnDevelop( "1.1.0", "- Pending change", "- Develop note" );
				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( currentBranch() ).toBe( "develop" );
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

			describe( "after a Gitflow finish that tagged a version without changing box.json", function(){
				it( "fixes a finished hotfix and publishes it", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug" );

					var result = fixtureProcess.runCommand( fixtureRoot, "release publish --fixTag --skipTests" );
					expectCommand( result, "release publish --fixTag after a hotfix finish" );
					expect( result.output ).toInclude( "git switch -c hotfix/1.0.1" );
					expect( result.output ).toInclude( "Created hotfix/1.0.1 from master." );
					expect( result.output ).toInclude( "Deleted the local tag v1.0.1." );
					expectFixed( "1.0.1", "v1.0.1", "- Fix the bug" );
					expect( git( [ "branch", "--list", "hotfix/*" ] ) ).toBe( "" );
				} );

				it( "keeps develop's own notes above and below the hotfix note", function(){
					for ( var order in [ "above", "below" ] ) {
						resetFixture();
						finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug", "- Develop note", order );

						var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --fixTag --skipTests" );
						expectCommand( result, "release gitflow --fixTag with a develop note #order# the hotfix note" );
						expectFixed( "1.0.1", "v1.0.1", "- Fix the bug" );
						expectReleasedOnDevelop( "1.0.1", "- Fix the bug", "- Develop note" );
					}
				} );

				it( "fixes a finished release on a release branch", function(){
					finishWithoutVersion( "release/1.1.0", "v1.1.0", "- New feature" );

					var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --fixTag --skipTests" );
					expectCommand( result, "release gitflow --fixTag after a release finish" );
					expect( result.output ).toInclude( "Created release/1.1.0 from master." );
					expect( git( [ "log", "-1", "master", "--pretty=%s" ] ) ).toInclude( "Merge branch 'release/1.1.0'" );
					expectFixed( "1.1.0", "v1.1.0", "- New feature" );
				} );

				it( "keeps the prerelease label of the tag", function(){
					finishWithoutVersion( "release/1.1.0-rc.1", "v1.1.0-rc.1", "- New feature" );

					var result = fixtureProcess.runCommand( fixtureRoot, "release publish --fixTag --skipTests" );
					expectCommand( result, "release publish --fixTag for a prerelease tag" );
					expectFixed( "1.1.0-rc.1", "v1.1.0-rc.1", "- New feature" );
				} );

				it( "reuses a finished branch that GitKraken kept", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug", "", "above", true );

					var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --fixTag --skipTests" );
					expectCommand( result, "release gitflow --fixTag with a kept hotfix branch" );
					expectFixed( "1.0.1", "v1.0.1", "- Fix the bug" );
				} );

				it( "stops without changes when the kept branch has new commits", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug", "", "above", true );
					gitOk( [ "switch", "hotfix/1.0.1" ] );
					fileWrite( fixtureRoot & "/source.txt", "fixed again" );
					commitAll( "Another fix" );
					gitOk( [ "switch", "master" ] );
					var refsBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );

					var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --fixTag --skipTests" );
					expect( result.exitCode ).notToBe( 0 );
					expect( result.output ).toInclude( "hotfix/1.0.1 already exists and has commits that are not on master" );
					expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( refsBefore );
				} );

				it( "stops without changes when origin's production branch has newer commits", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug" );
					gitOk( [ "push", "origin", "master" ] );
					var otherRoot = fixtureRoot & "-other";
					try {
						expectGit( fixtureProcess.runGit( getDirectoryFromPath( fixtureRoot ), [ "clone", "--branch", "master", originRoot, otherRoot ] ) );
						expectGit( fixtureProcess.runGit( otherRoot, [ "config", "user.email", "tests@example.com" ] ) );
						expectGit( fixtureProcess.runGit( otherRoot, [ "config", "user.name", "Release Tests" ] ) );
						fileWrite( otherRoot & "/other.txt", "from origin" );
						expectGit( fixtureProcess.runGit( otherRoot, [ "add", "." ] ) );
						expectGit( fixtureProcess.runGit( otherRoot, [ "commit", "-m", "Upstream change" ] ) );
						expectGit( fixtureProcess.runGit( otherRoot, [ "push", "origin", "master" ] ) );
					} finally {
						deleteDirectory( otherRoot );
					}
					var masterBefore = git( [ "rev-parse", "master" ] );

					var result = fixtureProcess.runCommand( fixtureRoot, "release publish --fixTag --skipTests" );
					expect( result.exitCode ).notToBe( 0 );
					expect( result.output ).toInclude( "origin/master has commits that are not in v1.0.1. Nothing was changed." );
					expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
					expect( git( [ "tag", "--points-at", "master" ] ) ).toBe( "v1.0.1" );
					expect( git( [ "branch", "--list", "hotfix/*" ] ) ).toBe( "" );
				} );

				it( "shows the steps in a practice run without changing anything", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug" );
					var refsBefore    = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );
					var packageBefore = fileRead( fixtureRoot & "/box.json" );

					var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --fixTag --dryRun --skipTests" );
					expectCommand( result, "the practice run of --fixTag" );
					expect( result.output ).toInclude( "git switch -c hotfix/1.0.1 master" );
					expect( result.output ).toInclude( "git tag -d v1.0.1" );
					expect( result.output ).toInclude( "No package was built." );
					expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( refsBefore );
					expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				} );

				it( "shows the manual steps and the flag when nobody can answer the question", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug" );
					var refsBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );

					for ( var commandLine in [ "release publish --skipTests", "release gitflow --skipTests" ] ) {
						var result = fixtureProcess.runCommand( fixtureRoot, commandLine );
						expect( result.exitCode ).notToBe( 0, commandLine );
						expect( result.output ).toInclude( "Tag v1.0.1 is on this commit, but box.json still has version 1.0.0" );
						expect( result.output ).toInclude( "git switch -c hotfix/1.0.1" );
						expect( result.output ).toInclude( "add --fixTag to the command" );
						expect( result.output ).notToInclude( "Do these steps now" );
					}
					expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( refsBefore );
				} );

				it( "does not fix the tag when the level gives another version", function(){
					finishWithoutVersion( "hotfix/1.0.1", "v1.0.1", "- Fix the bug" );
					var refsBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );

					var result = fixtureProcess.runCommand( fixtureRoot, "release publish minor --fixTag --skipTests" );
					expect( result.exitCode ).notToBe( 0 );
					expect( result.output ).toInclude( "The level you gave makes 1.1.0, but the tag is v1.0.1." );
					expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( refsBefore );
				} );
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

		// These projects list develop in prereleaseBranches. box release publish may then commit,
		// tag, and push a prerelease on develop. Stable versions still go through master.
		describe( "release publish on a prerelease branch", function(){
			beforeEach( function(){
				fixtureRoot = fixtureProcess.createProject();
				originRoot  = "";
				writeProject();
				usePrereleaseBranch( {} );
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
				deleteDirectory( originRoot );
			} );

			it( "publishes preminor alpha from develop and commits the release there", function(){
				var masterBefore = git( [ "rev-parse", "master" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish preminor alpha --skipTests" );
				expectCommand( result, "release publish preminor alpha on develop" );

				expect( result.output ).toInclude( "ok  on prerelease branch develop" );
				expect( result.output ).toInclude( "Up to date with origin/develop" );
				expect( result.output ).toInclude( "Released v1.1.0-alpha.1" );
				expect( currentBranch() ).toBe( "develop" );
				expect( versionOn( "develop" ) ).toBe( "1.1.0-alpha.1" );
				expect( git( [ "log", "-1", "develop", "--pretty=%s" ] ) ).toBe( "Release 1.1.0-alpha.1" );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
				expect( versionOn( "master" ) ).toBe( "1.0.0" );
				expect( fileExists( fixtureRoot & "/.artifacts/sample/1.1.0-alpha.1/sample-1.1.0-alpha.1.zip" ) ).toBeTrue();

				// A prerelease branch is a release build, so the package gets a build ID and no snapshot marker.
				var staged = fileRead( fixtureRoot & "/.tmp/sample/source.txt" );
				expect( staged ).toInclude( "1.1.0-alpha.1+" );
				expect( staged ).notToInclude( "snapshot" );
			} );

			it( "shows develop in the practice push steps", function(){
				usePrereleaseBranch( { publish : { forgebox : false, github : true } } );
				var refsBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish preminor alpha --dryRun --skipTests" );
				expectCommand( result, "the practice run of preminor alpha on develop" );
				expect( result.output ).toInclude( "git tag v1.1.0-alpha.1" );
				expect( result.output ).toInclude( "git push origin develop" );
				expect( result.output ).toInclude( "git push origin v1.1.0-alpha.1" );
				expect( result.output ).toInclude( "--prerelease" );
				expect( result.output ).notToInclude( "git push origin master" );
				expect( result.output ).notToInclude( "This practice run is on" );
				expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( refsBefore );
			} );

			it( "publishes the next prerelease from develop", function(){
				expectCommand( fixtureProcess.runCommand( fixtureRoot, "release publish preminor alpha --skipTests" ), "the first alpha" );
				writeChangelog( "- Second change" );
				commitAll( "Second change" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish prerelease --skipTests" );
				expectCommand( result, "release publish prerelease on develop" );
				expect( versionOn( "develop" ) ).toBe( "1.1.0-alpha.2" );
				expect( git( [ "log", "-1", "develop", "--pretty=%s" ] ) ).toBe( "Release 1.1.0-alpha.2" );
				expect( versionOn( "master" ) ).toBe( "1.0.0" );
			} );

			it( "stops a stable level on develop and points to box release gitflow", function(){
				var packageBefore = fileRead( fixtureRoot & "/box.json" );
				var commitsBefore = git( [ "rev-list", "--count", "HEAD" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish minor --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "develop can publish only prerelease versions, and 1.1.0 is stable" );
				expect( result.output ).toInclude( "box release gitflow minor" );
				expect( result.output ).toInclude( "box release publish preminor alpha" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( git( [ "rev-list", "--count", "HEAD" ] ) ).toBe( commitsBefore );
			} );

			it( "stops publish without a level on develop when box.json holds a stable version", function(){
				// The released tag sits on master. The branch message must come before the tag message.
				gitOk( [ "tag", "v1.0.0", "master" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "develop can publish only prerelease versions, and 1.0.0 is stable" );
				expect( result.output ).toInclude( "box release publish preminor alpha" );
				expect( result.output ).notToInclude( "points to a different commit" );
			} );

			it( "stops on develop when prereleaseBranches is empty", function(){
				writeSettings( {} );
				commitAll( "No prerelease branches" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release publish preminor alpha --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "must run from production branch master" );
				expect( result.output ).toInclude( "To publish prereleases from develop, add it to ""prereleaseBranches"" in release.json." );
				expect( versionOn( "develop" ) ).toBe( "1.0.0" );
			} );

			// This command pushes develop and the tag to the local bare origin. The GitHub Release
			// step then fails because no remote uses GitHub. Nothing leaves this computer.
			it( "pushes develop and an existing prerelease tag before the GitHub Release", function(){
				expectCommand( fixtureProcess.runCommand( fixtureRoot, "release publish preminor alpha --skipTests" ), "the first alpha" );
				gitOk( [ "tag", "v1.1.0-alpha.1" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release resume" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "Pushed develop to origin" );
				expect( result.output ).toInclude( "Pushed tag v1.1.0-alpha.1 to origin" );
				expect( originCommit( "develop" ) ).toBe( git( [ "rev-parse", "develop" ] ) );
				expect( fixtureProcess.runGit( originRoot, [ "tag", "--list" ] ).output ).toInclude( "v1.1.0-alpha.1" );
			} );

			it( "keeps production in a gitflow practice run on develop", function(){
				usePrereleaseBranch( { publish : { forgebox : false, github : true } } );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow preminor alpha --dryRun --skipTests" );
				expectCommand( result, "the gitflow practice run of preminor alpha" );
				expect( result.output ).toInclude( "git switch -c release/1.1.0-alpha.1 develop" );
				// Once in the Gitflow steps (with develop) and once in the publish preview.
				expect( occurrences( result.output, "git push origin master" ) ).toBe( 2 );
				expect( result.output ).notToInclude( "git push origin develop" );
				expect( result.output ).notToInclude( "can publish only prerelease versions" );
			} );

			it( "reports the prerelease branch in release check", function(){
				var stable = fixtureProcess.runCommand( fixtureRoot, "release check" );
				expect( stable.output ).toInclude( "prerelease: develop" );
				expect( stable.output ).toInclude( "FIX   branch: current branch is develop. It can publish only prerelease versions, and 1.0.0 is stable" );

				setVersion( "1.1.0-alpha.1" );
				commitAll( "Start the alpha" );
				var prerelease = fixtureProcess.runCommand( fixtureRoot, "release check" );
				expect( prerelease.output ).toInclude( "ok    branch: develop (prerelease branch)" );
			} );

			it( "stops gitflow without a level on develop when box.json holds an unpublished prerelease", function(){
				setVersion( "1.1.0-alpha.3" );
				commitAll( "Release 1.1.0-alpha.3" );
				var refsBefore = git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "box.json has prerelease 1.1.0-alpha.3. Publish it on develop with: box release publish" );
				expect( result.output ).toInclude( "box release gitflow minor" );
				expect( git( [ "for-each-ref", "--format=%(refname) %(objectname)" ] ) ).toBe( refsBefore );
			} );

			it( "releases the final version after prereleases on develop", function(){
				setVersion( "1.1.0-alpha.3" );
				writeChangelogWithSection( "- Final note", "1.1.0-alpha.3", "- Alpha note" );
				commitAll( "Release 1.1.0-alpha.3" );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expectCommand( result, "release gitflow minor after an alpha line" );

				expect( versionOn( "master" ) ).toBe( "1.1.0" );
				expect( versionOn( "develop" ) ).toBe( "1.1.0" );
				var content   = git( [ "show", "master:CHANGELOG.md" ] );
				var finalAt   = find( "[1.1.0]", content );
				var finalNote = find( "- Final note", content );
				var alphaAt   = find( "[1.1.0-alpha.3]", content );
				var alphaNote = find( "- Alpha note", content );
				expect( finalAt ).toBeGT( 0 );
				expect( finalNote ).toBeGT( finalAt );
				expect( alphaAt ).toBeGT( finalNote );
				expect( alphaNote ).toBeGT( alphaAt );
				expect( changelogCount( "master", "- Alpha note" ) ).toBe( 1 );
				expect( currentBranch() ).toBe( "develop" );
			} );

			it( "explains the empty [Unreleased] after a prerelease", function(){
				setVersion( "1.1.0-alpha.3" );
				writeChangelogWithSection( "", "1.1.0-alpha.3", "- Alpha note" );
				commitAll( "Release 1.1.0-alpha.3" );
				var hint = "1.1.0-alpha.3 is a prerelease, so its notes stay in their own sections. Write the notes for 1.1.0 under [Unreleased].";

				var stableRun = fixtureProcess.runCommand( fixtureRoot, "release gitflow minor --skipTests" );
				expect( stableRun.exitCode ).notToBe( 0 );
				expect( stableRun.output ).toInclude( "is empty" );
				expect( stableRun.output ).toInclude( hint );

				var alphaRun = fixtureProcess.runCommand( fixtureRoot, "release publish prerelease --skipTests" );
				expect( alphaRun.exitCode ).notToBe( 0 );
				expect( alphaRun.output ).toInclude( "is empty" );
				expect( alphaRun.output ).notToInclude( "stay in their own sections" );
			} );

			it( "names the box.json version to keep when a hotfix meets a prerelease on develop", function(){
				setVersion( "1.1.0-alpha.2" );
				commitAll( "Release 1.1.0-alpha.2" );
				// The hotfix starts from master. In a real project, master got the setting with an
				// earlier release. The fixture's master is older, so the hotfix adds it.
				gitOk( [ "switch", "-c", "hotfix/1.0.1", "master" ] );
				writeSettings( { prereleaseBranches : [ "develop" ] } );
				fileWrite( fixtureRoot & "/fix.txt", "fixed" );
				commitAll( "Fix the bug" );
				var masterBefore = git( [ "rev-parse", "master" ] );

				var result = fixtureProcess.runCommand( fixtureRoot, "release gitflow --skipTests" );
				expect( result.exitCode ).notToBe( 0 );
				expect( result.output ).toInclude( "could not be merged into develop" );
				expect( result.output ).toInclude( "These files have conflicts: box.json" );
				expect( result.output ).toInclude( "Keep the newer version in box.json (1.1.0-alpha.2 on develop)." );
				expect( currentBranch() ).toBe( "hotfix/1.0.1" );
				expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
				expect( git( [ "rev-parse", "master" ] ) ).toBe( masterBefore );
			} );
		} );
	}

	// FIXTURE HELPERS

	/** Replaces the test project with a new one, for a test that checks more than one case. */
	private void function resetFixture(){
		deleteDirectory( fixtureRoot );
		deleteDirectory( originRoot );
		fixtureRoot = fixtureProcess.createProject();
		writeProject();
	}

	/**
	 * Finishes a branch the way GitKraken or git flow does when nobody changed the version first.
	 * Starts from a published 1.0.0 with an empty [Unreleased] on master, develop, and origin.
	 * The branch adds a note, merges into master and develop, and master gets the tag. box.json
	 * still has 1.0.0. Leaves master checked out, with nothing pushed after the merges.
	 *
	 * @branch      The finished branch. A release branch starts from develop, a hotfix from master.
	 * @tagName     The tag on master.
	 * @note        The note the branch adds under [Unreleased].
	 * @developNote A note develop adds while the branch is open. Develop's merge combines both.
	 * @order       Where the develop note goes: "above" or "below" the branch note.
	 * @keepBranch  Keeps the branch after the finish, like GitKraken's option.
	 */
	private void function finishWithoutVersion(
		required string branch,
		required string tagName,
		required string note,
		string developNote = "",
		string order       = "above",
		boolean keepBranch = false
	){
		writeChangelog( "" );
		commitAll( "Release the pending change" );
		gitOk( [ "branch", "-f", "master", "develop" ] );
		gitOk( [ "push", "origin", "master", "develop" ] );

		var isRelease = left( arguments.branch, 8 ) == "release/";
		gitOk( [ "switch", "-c", arguments.branch, isRelease ? "develop" : "master" ] );
		fileWrite( fixtureRoot & "/source.txt", "changed on " & arguments.branch );
		writeChangelog( arguments.note );
		commitAll( "Work on " & arguments.branch );

		if ( len( arguments.developNote ) ) {
			gitOk( [ "switch", "develop" ] );
			writeChangelog( arguments.developNote );
			commitAll( "Develop note" );
		}

		gitOk( [ "switch", "master" ] );
		gitOk( [ "merge", "--no-ff", "--no-edit", arguments.branch ] );
		gitOk( [ "tag", "-a", arguments.tagName, "-m", arguments.tagName ] );

		gitOk( [ "switch", "develop" ] );
		if ( fixtureProcess.runGit( fixtureRoot, [ "merge", "--no-ff", "--no-edit", arguments.branch ] ).exitCode != 0 ) {
			// Resolve the changelog conflict by hand, as a person would in GitKraken.
			var lf = chr( 10 );
			writeChangelog(
				arguments.order == "above"
					? arguments.developNote & lf & arguments.note
					: arguments.note & lf & arguments.developNote
			);
			gitOk( [ "add", "CHANGELOG.md" ] );
			gitOk( [ "commit", "--no-edit" ] );
		}
		if ( !arguments.keepBranch ) {
			gitOk( [ "branch", "-D", arguments.branch ] );
		}
		gitOk( [ "switch", "master" ] );
		expect( versionOn( "master" ) ).toBe( "1.0.0" );
	}

	/**
	 * Checks the result of a fixed Gitflow finish on both branches and on origin. GitHub
	 * publishing is off in these projects, so the release does not tag the new merge commit.
	 * The old local tag must be gone.
	 */
	private void function expectFixed( required string version, required string tagName, required string note ){
		expect( currentBranch() ).toBe( "develop" );
		expect( versionOn( "master" ) ).toBe( arguments.version );
		expect( versionOn( "develop" ) ).toBe( arguments.version );
		expect( git( [ "log", "-1", "master", "--pretty=%s" ] ) ).toInclude( "Merge branch" );
		expect( git( [ "tag", "--list", arguments.tagName ] ) ).toBe( "" );
		expect( originCommit( "master" ) ).toBe( git( [ "rev-parse", "master" ] ) );
		expect( originCommit( "develop" ) ).toBe( git( [ "rev-parse", "develop" ] ) );
		expect( changelogCount( "master", arguments.note ) ).toBe( 1 );
		expect( changelogCount( "develop", arguments.note ) ).toBe( 1 );
		expect( fileExists( fixtureRoot & "/.artifacts/sample/#arguments.version#/sample-#arguments.version#.zip" ) ).toBeTrue();
		expect( git( [ "status", "--porcelain" ] ) ).toBe( "" );
	}

	/**
	 * Checks that develop lists a note in the released section only, and keeps its own note under
	 * [Unreleased].
	 */
	private void function expectReleasedOnDevelop( required string version, required string releasedNote, required string developNote ){
		var content    = git( [ "show", "develop:CHANGELOG.md" ] );
		var sectionAt  = find( "[#arguments.version#]", content );
		var developAt  = find( arguments.developNote, content );
		var releasedAt = find( arguments.releasedNote, content );
		expect( sectionAt ).toBeGT( 0 );
		expect( developAt ).toBeGT( 0 );
		expect( developAt ).toBeLT( sectionAt, "the develop note stays under [Unreleased]" );
		expect( releasedAt ).toBeGT( sectionAt, "the released note is in the new section" );
		expect( changelogCount( "develop", arguments.releasedNote ) ).toBe( 1 );
		expect( changelogCount( "develop", arguments.developNote ) ).toBe( 1 );
	}

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
	 * Lists develop as a prerelease branch, puts build tokens in source.txt, and commits the
	 * change on develop. Other settings can change at the same time.
	 */
	private void function usePrereleaseBranch( required struct overrides ){
		var settings = { prereleaseBranches : [ "develop" ] };
		structAppend( settings, arguments.overrides, true );
		writeSettings( settings );
		fileWrite( fixtureRoot & "/source.txt", "release fixture @build.version@+@build.number@" );
		commitAll( "Use develop for prereleases" );
		gitOk( [ "push", "origin", "develop" ] );
	}

	/**
	 * Writes the changelog with [Unreleased] notes and one released section above [1.0.0], as it
	 * looks after a prerelease was published. An empty value leaves [Unreleased] empty.
	 */
	private void function writeChangelogWithSection( required string unreleased, required string version, required string notes ){
		var lf      = chr( 10 );
		var heading = repeatString( chr( 35 ), 2 ) & " ";
		fileWrite(
			fixtureRoot & "/CHANGELOG.md",
			heading & "[Unreleased]" & lf & lf
				& ( len( arguments.unreleased ) ? arguments.unreleased & lf & lf : "" )
				& heading & "[#arguments.version#] - 2026-10-20" & lf & lf & arguments.notes & lf & lf
				& heading & "[1.0.0] - 2026-08-07" & lf & lf & "- First release" & lf
		);
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
		return occurrences( git( [ "show", arguments.branch & ":CHANGELOG.md" ] ), arguments.text );
	}

	/** Returns how many times a text appears in a string. */
	private numeric function occurrences( required string content, required string text ){
		return ( len( arguments.content ) - len( replace( arguments.content, arguments.text, "", "all" ) ) ) / len( arguments.text );
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
