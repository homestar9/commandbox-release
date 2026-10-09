/**
 * Checks RepositoryService against real Git repositories. Each test builds a project with a
 * local bare repository as its remote. The remote is named upstream, not origin, so the tests
 * also check that every command uses the bound remote.
 */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "RepositoryService", function(){
			beforeEach( function(){
				processRunner = model( "ProcessRunner" );
				fixtureRoot   = createTempProject();
				remoteRoot    = fixtureRoot & "-remote.git";
				otherRoot     = "";
				outsideRoot   = "";

				gitOk( [ "init" ] );
				gitOk( [ "symbolic-ref", "HEAD", "refs/heads/master" ] );
				configureUser( fixtureRoot );
				fileWrite( fixtureRoot & "/source.txt", "first" );
				commitAll( "First" );

				directoryCreate( remoteRoot, true, true );
				gitOk( [ "init", "--bare" ], remoteRoot );
				gitOk( [ "remote", "add", "upstream", remoteRoot ] );
				gitOk( [ "push", "-u", "upstream", "master" ] );

				repo = model( "RepositoryService" ).forRoot( fixtureRoot, "upstream" );
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
				deleteDirectory( remoteRoot );
				deleteDirectory( otherRoot );
				deleteDirectory( outsideRoot );
			} );

			describe( "repository state", function(){
				it( "reads the branch, commit, and remote", function(){
					expect( repo.remoteName() ).toBe( "upstream" );
					expect( repo.remoteUrl() ).toInclude( "-remote.git" );
					expect( repo.currentBranch() ).toBe( "master" );
					expect( repo.headCommit() ).toBe( gitOut( [ "rev-parse", "HEAD" ] ) );
					expect( repo.canReachRemote().ok ).toBeTrue();
				} );

				it( "returns HEAD for a detached checkout", function(){
					gitOk( [ "switch", "--detach" ] );
					expect( repo.currentBranch() ).toBe( "HEAD" );
				} );

				it( "reports a missing remote as an empty URL and an unreachable remote", function(){
					var other = model( "RepositoryService" ).forRoot( fixtureRoot, "missing" );
					expect( other.remoteUrl() ).toBe( "" );
					expect( other.canReachRemote().ok ).toBeFalse();
				} );

				it( "lists uncommitted changes", function(){
					expect( repo.changedFiles() ).toBeEmpty();
					fileWrite( fixtureRoot & "/source.txt", "changed" );
					expect( arrayLen( repo.changedFiles() ) ).toBe( 1 );
				} );

				it( "throws Release.Git outside a Git repository", function(){
					// The system temp folder is outside this checkout, so Git cannot find a parent repository.
					outsideRoot = replace( getTempDirectory(), "\", "/", "all" ) & "commandbox-release-spec-" & createUUID();
					directoryCreate( outsideRoot, true, true );
					var outside = model( "RepositoryService" ).forRoot( outsideRoot );
					expect( function(){
						outside.changedFiles();
					} ).toThrow( "Release.Git" );
					expect( function(){
						outside.currentBranch();
					} ).toThrow( "Release.Git" );
				} );
			} );

			describe( "tagRelease", function(){
				it( "returns new when no tag exists", function(){
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "new" );
					expect( tag.local ).toBe( "missing" );
					expect( tag.remote ).toBe( "missing" );
				} );

				it( "returns existing for a local tag at this commit that the remote does not have", function(){
					gitOk( [ "tag", "v1.0.0" ] );
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "existing" );
					expect( tag.remote ).toBe( "missing" );
				} );

				it( "returns existing for a tag at this commit that is already on the remote", function(){
					gitOk( [ "tag", "v1.0.0" ] );
					gitOk( [ "push", "upstream", "v1.0.0" ] );
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "existing" );
					expect( tag.remote ).toBe( "present" );
					expect( tag.remoteCommit ).toBe( repo.headCommit() );
				} );

				it( "reads the tagged commit of an annotated tag on the remote", function(){
					gitOk( [ "tag", "-a", "v1.0.0", "-m", "Release 1.0.0" ] );
					gitOk( [ "push", "upstream", "v1.0.0" ] );
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "existing" );
					expect( tag.remoteCommit ).toBe( repo.headCommit() );
				} );

				it( "returns a conflict when the local tag points to another commit", function(){
					gitOk( [ "tag", "v1.0.0" ] );
					fileWrite( fixtureRoot & "/source.txt", "second" );
					commitAll( "Second" );
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "conflict" );
					expect( tag.reason ).toBe( "localElsewhere" );
				} );

				it( "returns a conflict when the remote tag points to another commit", function(){
					gitOk( [ "tag", "v1.0.0" ] );
					gitOk( [ "push", "upstream", "v1.0.0" ] );
					gitOk( [ "tag", "-d", "v1.0.0" ] );
					fileWrite( fixtureRoot & "/source.txt", "second" );
					commitAll( "Second" );
					gitOk( [ "tag", "v1.0.0" ] );
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "conflict" );
					expect( tag.reason ).toBe( "remoteElsewhere" );
					expect( tag.local ).toBe( "atHead" );
				} );

				it( "returns a conflict when only the remote has the tag", function(){
					gitOk( [ "tag", "v1.0.0" ] );
					gitOk( [ "push", "upstream", "v1.0.0" ] );
					gitOk( [ "tag", "-d", "v1.0.0" ] );
					var tag = repo.tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "conflict" );
					expect( tag.reason ).toBe( "remoteOnly" );
				} );

				it( "returns a conflict when the remote cannot be checked", function(){
					var tag = model( "RepositoryService" ).forRoot( fixtureRoot, "missing" ).tagRelease( "v1.0.0" );
					expect( tag.mode ).toBe( "conflict" );
					expect( tag.reason ).toBe( "remoteUnknown" );
					expect( tag.remote ).toBe( "unknown" );
				} );

				it( "creates a tag at the current commit", function(){
					repo.createTag( "v1.0.0" );
					expect( repo.localTag( "v1.0.0" ) ).toBe( "atHead" );
					expect( function(){
						repo.createTag( "v1.0.0" );
					} ).toThrow( "Release.Git" );
				} );
			} );

			describe( "branches", function(){
				it( "reads Gitflow settings and their defaults", function(){
					var defaults = repo.gitflowBranches();
					expect( defaults.production ).toBe( "" );
					expect( defaults.develop ).toBe( "develop" );
					expect( defaults.releasePrefix ).toBe( "release/" );
					expect( defaults.hotfixPrefix ).toBe( "hotfix/" );

					gitOk( [ "config", "gitflow.branch.master", "main" ] );
					gitOk( [ "config", "gitflow.prefix.release", "rel-" ] );
					var configured = repo.gitflowBranches();
					expect( configured.production ).toBe( "main" );
					expect( configured.releasePrefix ).toBe( "rel-" );
				} );

				it( "finds branches, files, and history", function(){
					gitOk( [ "branch", "release/1.1.0" ] );
					gitOk( [ "branch", "release/1.2.0" ] );
					expect( repo.branchExists( "release/1.1.0" ) ).toBeTrue();
					expect( repo.branchExists( "release/9.9.9" ) ).toBeFalse();
					expect( repo.remoteBranchExists( "master" ) ).toBeTrue();
					expect( arrayToList( repo.branchesWithPrefix( "release/" ) ) ).toBe( "release/1.1.0,release/1.2.0" );
					expect( repo.fileAt( "refs/heads/master", "source.txt" ) ).toBe( "first" );
					expect( repo.fileAt( "refs/heads/master", "missing.txt" ) ).toBe( "" );

					var first = repo.headCommit();
					fileWrite( fixtureRoot & "/source.txt", "second" );
					commitAll( "Second" );
					expect( repo.isAncestor( first, "HEAD" ) ).toBeTrue();
					expect( repo.isAncestor( "HEAD", first ) ).toBeFalse();
					expect( repo.treeOf( "HEAD" ) ).notToBe( repo.treeOf( first ) );
				} );

				it( "compares the remote branch with the current commit", function(){
					expect( repo.remoteBranchState( "master" ) ).toBe( "contains" );
					expect( repo.remoteBranchState( "missing" ) ).toBe( "missing" );
					fileWrite( fixtureRoot & "/source.txt", "second" );
					commitAll( "Second" );
					expect( repo.remoteBranchState( "master" ) ).toBe( "behind" );
					expect( model( "RepositoryService" ).forRoot( fixtureRoot, "missing" ).remoteBranchState( "master" ) ).toBe( "unknown" );
				} );

				it( "reports a diverged remote branch, fetched or not", function(){
					pushFromOtherClone( "master" );
					expect( repo.remoteBranchState( "master" ) ).toBe( "diverged" );
					repo.fetch();
					fileWrite( fixtureRoot & "/local.txt", "local" );
					commitAll( "Local" );
					expect( repo.remoteBranchState( "master" ) ).toBe( "diverged" );
				} );

				it( "fast-forwards the current branch and another branch from the remote", function(){
					gitOk( [ "branch", "develop" ] );
					gitOk( [ "push", "upstream", "develop" ] );
					pushFromOtherClone( "master" );
					pushFromOtherClone( "develop" );

					repo.fetch();
					expect( repo.fastForward( "master", "master" ) ).toBe( "updated" );
					expect( repo.fastForward( "develop", "master" ) ).toBe( "updated" );
					expect( repo.fastForward( "master", "master" ) ).toBe( "current" );
					expect( repo.headCommit() ).toBe( gitOut( [ "rev-parse", "upstream/master" ] ) );
					expect( gitOut( [ "rev-parse", "develop" ] ) ).toBe( gitOut( [ "rev-parse", "upstream/develop" ] ) );
					expect( repo.fastForward( "no-remote-copy", "master" ) ).toBe( "current" );
				} );

				it( "leaves a branch unchanged when it and the remote both have new commits", function(){
					pushFromOtherClone( "master" );
					fileWrite( fixtureRoot & "/local.txt", "local" );
					commitAll( "Local" );
					var before = repo.headCommit();

					repo.fetch();
					expect( repo.fastForward( "master", "master" ) ).toBe( "diverged" );
					expect( repo.headCommit() ).toBe( before );
				} );

				it( "cancels a merge with conflicts", function(){
					gitOk( [ "switch", "-c", "feature" ] );
					fileWrite( fixtureRoot & "/source.txt", "feature change" );
					commitAll( "Feature change" );
					gitOk( [ "switch", "master" ] );
					fileWrite( fixtureRoot & "/source.txt", "master change" );
					commitAll( "Master change" );
					var before = repo.headCommit();

					expect( function(){
						repo.merge( "feature" );
					} ).toThrow( "Release.Git" );
					expect( repo.changedFiles() ).toBeEmpty();
					expect( repo.headCommit() ).toBe( before );
				} );

				it( "merges with a merge commit, then pushes and deletes branches", function(){
					repo.createBranch( "topic", "master" );
					fileWrite( fixtureRoot & "/topic.txt", "topic" );
					commitAll( "Topic" );
					repo.switchTo( "master" ).merge( "topic" );
					expect( gitOut( [ "log", "-1", "--pretty=%s" ] ) ).toInclude( "Merge branch 'topic'" );

					repo.push( [ "master", "topic" ] );
					expect( repo.remoteBranchState( "master" ) ).toBe( "contains" );
					expect( repo.deleteRemoteBranch( "topic" ) ).toBeTrue();
					expect( repo.deleteRemoteBranch( "topic" ) ).toBeFalse();
					repo.deleteBranch( "topic" );
					expect( repo.branchExists( "topic" ) ).toBeFalse();
				} );

				it( "commits only the listed files", function(){
					fileWrite( fixtureRoot & "/source.txt", "release" );
					fileWrite( fixtureRoot & "/other.txt", "not released" );
					repo.commitFiles( [ "source.txt" ], "Release 1.0.1" );
					expect( gitOut( [ "log", "-1", "--pretty=%s" ] ) ).toBe( "Release 1.0.1" );
					expect( arrayToList( repo.changedFiles() ) ).toInclude( "other.txt" );
				} );
			} );
		} );
	}

	// FIXTURE HELPERS

	/** Pushes one new commit to a branch on the remote from a second clone. */
	private void function pushFromOtherClone( required string branch ){
		otherRoot = fixtureRoot & "-other";
		if ( !directoryExists( otherRoot ) ) {
			gitOk( [ "clone", remoteRoot, otherRoot ], getDirectoryFromPath( fixtureRoot ) );
			configureUser( otherRoot );
		}
		gitOk( [ "switch", arguments.branch ], otherRoot );
		fileWrite( otherRoot & "/upstream-#arguments.branch#.txt", "from the remote" );
		gitOk( [ "add", "." ], otherRoot );
		gitOk( [ "commit", "-m", "Upstream change" ], otherRoot );
		gitOk( [ "push", "origin", arguments.branch ], otherRoot );
	}

	private void function configureUser( required string root ){
		gitOk( [ "config", "user.email", "tests@example.com" ], arguments.root );
		gitOk( [ "config", "user.name", "Release Tests" ], arguments.root );
	}

	private void function commitAll( required string message ){
		gitOk( [ "add", "." ] );
		gitOk( [ "commit", "-m", arguments.message ] );
	}

	/** Runs Git and returns its trimmed output. */
	private string function gitOut( required array args, string root = fixtureRoot ){
		return trim( processRunner.run( "git", arguments.args, arguments.root ).output );
	}

	/** Runs Git and fails the test when Git fails. */
	private void function gitOk( required array args, string root = fixtureRoot ){
		expectCommand( processRunner.run( "git", arguments.args, arguments.root ), "git " & arrayToList( arguments.args, " " ) );
	}
}
