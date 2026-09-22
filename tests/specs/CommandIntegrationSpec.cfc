/** Runs real release commands in temporary projects with local Git repositories. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Release command integration", function(){
			beforeEach( function(){
				fixtureProcess = new tests.support.FixtureProcess( repoRoot() );
				fixtureRoot    = fixtureProcess.createProject();
				originRoot     = "";
			} );

			afterEach( function(){
				deleteDirectory( fixtureRoot );
				deleteDirectory( originRoot );
			} );

			it( "sets up a module without changing box.json scripts", function(){
				writeJSON(
					fixtureRoot & "/box.json",
					{
						name    : "Sample module",
						slug    : "sample-module",
						version : "1.0.0",
						type    : "commandbox-modules",
						testbox : { runner : "http://127.0.0.1:61000/tests/runner.cfm" },
						scripts : { "release" : "keep this command" },
						ignore  : [ "/custom/" ]
					}
				);
				writeJSON( fixtureRoot & "/server-lucee@5.json", { app : { cfengine : "lucee@5" } } );

				var initResult = fixtureProcess.runCommand( fixtureRoot, "release init --yes" );
				expectCommand( initResult, "release init" );

				var packageData = deserializeJSON( fileRead( fixtureRoot & "/box.json" ) );
				var settings    = deserializeJSON( fileRead( fixtureRoot & "/release.json" ) );
				expect( packageData.scripts.release ).toBe( "keep this command" );
				expect( packageData.ignore[ 1 ] ).toBe( "/custom/" );
				expect( arrayToList( packageData.ignore ) ).toInclude( "/tests/" );
				expect( arrayToList( packageData.ignore ) ).toInclude( "**/.*" );
				expect( arrayToList( packageData.ignore ) ).toInclude( "/modules/" );
				expect( settings ).notToHaveKey( "projectType" );
				expect( settings.requires ).toBe( moduleVersion() );
				expect( settings.testRunner ).toBe( "http://127.0.0.1:61000/tests/runner.cfm" );
				expect( settings.publish.forgebox ).toBeTrue();
				expect( settings.publish.github ).toBeTrue();
				expect( settings.engines[ 1 ].name ).toBe( "Lucee 5" );
				expect( settings ).notToHaveKey( "excludes" );
				expect( fileExists( fixtureRoot & "/CHANGELOG.md" ) ).toBeTrue();
				expect( fileExists( fixtureRoot & "/RELEASE.md" ) ).toBeFalse();
				expect( fileRead( fixtureRoot & "/.gitignore" ) ).toInclude( ".artifacts/" );

				var settingsBeforeSecondRun = fileRead( fixtureRoot & "/release.json" );
				var packageBeforeSecondRun  = fileRead( fixtureRoot & "/box.json" );
				var secondRun = fixtureProcess.runCommand( fixtureRoot, "release init --yes --docs" );
				expectCommand( secondRun, "the second release init" );
				expect( fileRead( fixtureRoot & "/release.json" ) ).toBe( settingsBeforeSecondRun );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBeforeSecondRun );
				expect( secondRun.output ).toInclude( "already has the recommended patterns" );
				expect( fileExists( fixtureRoot & "/RELEASE.md" ) ).toBeTrue();

				writeJSON( fixtureRoot & "/release.json", { custom : true } );
				expectCommand( fixtureProcess.runCommand( fixtureRoot, "release init --yes --force" ), "the forced release init" );
				var forcedSettings = deserializeJSON( fileRead( fixtureRoot & "/release.json" ) );
				expect( forcedSettings ).toHaveKey( "publish" );
				expect( forcedSettings ).notToHaveKey( "custom" );
			} );

			it( "sets up a web app that publishes to GitHub only", function(){
				writeJSON( fixtureRoot & "/box.json", { name : "Site", slug : "site", version : "1.0.0", type : "mvc" } );

				expectCommand( fixtureProcess.runCommand( fixtureRoot, "release init --yes" ), "release init for an app" );

				var settings = deserializeJSON( fileRead( fixtureRoot & "/release.json" ) );
				var ignore   = arrayToList( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).ignore );
				expect( settings ).notToHaveKey( "projectType" );
				expect( settings.publish.forgebox ).toBeFalse();
				expect( settings.publish.github ).toBeTrue();
				expect( ignore ).toInclude( "!/.htaccess" );
				expect( ignore ).notToInclude( "/modules/" );
			} );

			it( "explains how to upgrade a project that still has build.json", function(){
				writeBasicProject( "1.0.0" );
				fileDelete( fixtureRoot & "/release.json" );
				writeJSON( fixtureRoot & "/build.json", { branch : "master" } );

				var checkResult = fixtureProcess.runCommand( fixtureRoot, "release check" );
				expect( checkResult.exitCode ).notToBe( 0 );
				expect( checkResult.output ).toInclude( "Upgrading from 1.x or 2.x" );
			} );

			it( "shows a version change before applying the same change", function(){
				writeBasicProject( "1.2.3" );
				writeChangelog( true );
				var packageBefore   = fileRead( fixtureRoot & "/box.json" );
				var changelogBefore = fileRead( fixtureRoot & "/CHANGELOG.md" );

				var dryRun = fixtureProcess.runCommand( fixtureRoot, "release bump patch --dryRun" );
				expectCommand( dryRun, "the version practice run" );
				expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				expect( fileRead( fixtureRoot & "/CHANGELOG.md" ) ).toBe( changelogBefore );

				var bump = fixtureProcess.runCommand( fixtureRoot, "release bump patch" );
				expectCommand( bump, "release bump patch" );
				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.2.4" );
				expect( fileRead( fixtureRoot & "/CHANGELOG.md" ) ).toInclude( versionHeading( "1.2.4" ) );
				expect( bump.output ).toInclude( "box release publish" );
			} );

			it( "stops beta and alpha changes from changing an active prerelease target", function(){
				for ( var preid in [ "beta", "alpha" ] ) {
					writeBasicProject( "1.2.0-#preid#.3" );
					writeChangelog( true );
					var packageBefore = fileRead( fixtureRoot & "/box.json" );

					var guardedBump = fixtureProcess.runCommand( fixtureRoot, "release bump preminor #preid#" );
					expect( guardedBump.exitCode ).notToBe( 0 );
					expect( guardedBump.output ).toInclude( "release bump prerelease" );
					expect( fileRead( fixtureRoot & "/box.json" ) ).toBe( packageBefore );
				}
			} );

			it( "changes a prerelease target when the flag allows it", function(){
				writeBasicProject( "1.2.0-rc.2" );
				writeChangelog( true );

				var guardedBump = fixtureProcess.runCommand( fixtureRoot, "release bump preminor beta" );
				expect( guardedBump.exitCode ).notToBe( 0 );
				expect( guardedBump.output ).toInclude( "allowPrereleaseRetarget" );

				var allowedBump = fixtureProcess.runCommand( fixtureRoot, "release bump preminor beta --allowPrereleaseRetarget" );
				expectCommand( allowedBump, "the allowed prerelease target change" );
				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.3.0-beta.1" );
			} );

			it( "starts a prerelease from a final version", function(){
				writeBasicProject( "1.0.0" );
				writeChangelog( true );
				var bump = fixtureProcess.runCommand( fixtureRoot, "release bump preminor alpha" );
				expectCommand( bump, "the stable alpha bump" );
				expect( deserializeJSON( fileRead( fixtureRoot & "/box.json" ) ).version ).toBe( "1.1.0-alpha.1" );
			} );

			it( "packages the files that the box.json ignore list allows", function(){
				writeBasicProject( "1.0.0", false, [ "/tests/", "**/*.bak", "/docs/private/" ] );
				fileWrite( fixtureRoot & "/version.txt", "@build.version@+@build.number@" );
				fileWrite( fixtureRoot & "/ModuleConfig.cfc", "component {}" );
				writeFile( "tests/not-shipped.txt", "excluded by an anchored folder pattern" );
				writeFile( "docs/public/guide.txt", "shipped" );
				writeFile( "docs/private/secret.txt", "excluded by a nested anchored pattern" );
				writeFile( "models/sub/deep.cfc", "component {}" );
				writeFile( "notes.bak", "excluded at the root" );
				writeFile( "models/notes.bak", "excluded at every depth" );
				writeFile( "modules/shipped/file.txt", "shipped even though .gitignore lists modules/" );
				fileWrite( fixtureRoot & "/.gitignore", "modules/" & chr( 10 ) );
				directoryCreate( fixtureRoot & "/emptydir", true, true );

				var buildResult = fixtureProcess.runCommand(
					fixtureRoot,
					"release package projectName=sample version=1.0.0 buildID=abc1234 branch=master --skipTests"
				);
				expectCommand( buildResult, "release package" );

				var artifactRoot = fixtureRoot & "/.artifacts/sample/1.0.0";
				var zipPath      = artifactRoot & "/sample-1.0.0.zip";
				expect( fileExists( zipPath ) ).toBeTrue();
				expect( fileExists( zipPath & ".sha512" ) ).toBeTrue();
				expect( fileExists( zipPath & ".md5" ) ).toBeTrue();

				cfzip( action = "read", file = zipPath, entrypath = "version.txt", variable = "local.versionText" );
				expect( local.versionText ).toBe( "1.0.0+abc1234" );
				var zipNames = zipEntryNames( zipPath );
				expect( zipNames ).toInclude( "models/sub/deep.cfc" );
				expect( zipNames ).toInclude( "docs/public/guide.txt" );
				expect( zipNames ).toInclude( "modules/shipped/file.txt" );
				expect( zipNames ).toInclude( "ModuleConfig.cfc" );
				expect( zipNames ).notToInclude( "tests/not-shipped.txt" );
				expect( zipNames ).notToInclude( "docs/private/secret.txt" );
				expect( zipNames ).notToInclude( "notes.bak" );
				expect( zipNames ).notToInclude( "models/notes.bak" );
				expect( zipNames ).notToInclude( "release.json" );
				expect( zipNames ).notToInclude( ".gitignore" );

				var staging = fixtureRoot & "/.tmp/sample";
				expect( directoryExists( staging & "/emptydir" ) ).toBeTrue( "empty folders survive" );
				expect( fileExists( staging & "/.gitignore" ) ).toBeFalse();
				expect( directoryExists( staging & "/.tmp" ) ).toBeFalse();
				expect( directoryExists( staging & "/.artifacts" ) ).toBeFalse();
			} );

			it( "keeps custom staging and artifact folders out of the package", function(){
				writeBasicProject( "1.0.0", false, [], { stagingDir : "build-staging", artifactsDir : "build-out" } );
				fileWrite( fixtureRoot & "/source.txt", "shipped" );

				expectCommand(
					fixtureProcess.runCommand( fixtureRoot, "release package projectName=sample version=1.0.0 buildID=abc1234 branch=master --skipTests" ),
					"release package with custom folders"
				);
				var staging = fixtureRoot & "/build-staging/sample";
				expect( fileExists( staging & "/source.txt" ) ).toBeTrue();
				expect( directoryExists( staging & "/build-staging" ) ).toBeFalse();
				expect( directoryExists( staging & "/build-out" ) ).toBeFalse();
				expect( fileExists( fixtureRoot & "/build-out/sample/1.0.0/sample-1.0.0.zip" ) ).toBeTrue();
			} );

			it( "keeps .htaccess and .well-known in a web app package", function(){
				writeBasicProject( "1.0.0", false, [ "**/.*", "!/.htaccess", "!/.well-known/" ], {}, "mvc" );
				fileWrite( fixtureRoot & "/index.cfm", "site" );
				fileWrite( fixtureRoot & "/.htaccess", "RewriteEngine On" );
				fileWrite( fixtureRoot & "/.hidden", "not shipped" );
				writeFile( ".well-known/acme-challenge/token.txt", "shipped" );
				writeFile( ".github/workflows/ci.yml", "not shipped" );

				expectCommand(
					fixtureProcess.runCommand( fixtureRoot, "release package projectName=site version=1.0.0 buildID=abc1234 branch=master --skipTests" ),
					"release package for an app"
				);
				var zipNames = zipEntryNames( fixtureRoot & "/.artifacts/site/1.0.0/site-1.0.0.zip" );
				expect( zipNames ).toInclude( "index.cfm" );
				expect( zipNames ).toInclude( ".htaccess" );
				expect( zipNames ).toInclude( ".well-known/acme-challenge/token.txt" );
				expect( zipNames ).notToInclude( ".hidden" );
				expect( zipNames ).notToInclude( ".github/workflows/ci.yml" );
			} );

			it( "stops when the ignore list removes a required file", function(){
				writeBasicProject( "1.0.0", false, [ "/ModuleConfig.cfc" ] );
				fileWrite( fixtureRoot & "/ModuleConfig.cfc", "component {}" );

				var buildResult = fixtureProcess.runCommand( fixtureRoot, "release package projectName=sample version=1.0.0 buildID=abc1234 branch=master --skipTests" );
				expect( buildResult.exitCode ).notToBe( 0 );
				expect( buildResult.output ).toInclude( "ModuleConfig.cfc" );
				expect( buildResult.output ).toInclude( "ignore list" );
			} );

			it( "runs a release practice run without creating or pushing a tag", function(){
				writeBasicProject( "1.0.0", true );
				writeChangelog( false, "1.0.0" );
				fileWrite( fixtureRoot & "/source.txt", "release fixture" );
				createLocalGitRemote();

				var releaseResult = fixtureProcess.runCommand( fixtureRoot, "release publish --dryRun --skipTests" );
				expectCommand( releaseResult, "the release practice run" );
				expect( releaseResult.output ).toInclude( "Nothing will be published, tagged, or pushed" );
				expect( fixtureProcess.runGit( fixtureRoot, [ "tag", "--list" ] ).output ).toBe( "" );
				expect( fixtureProcess.runGit( originRoot, [ "tag", "--list" ] ).output ).toBe( "" );
			} );

			it( "finds the project when a command runs from a child folder", function(){
				writeBasicProject( "1.0.0" );
				directoryCreate( fixtureRoot & "/models", true, true );
				var checkResult = fixtureProcess.runCommand( fixtureRoot & "/models", "release check" );
				expectCommand( checkResult, "release check from a subfolder" );
				expect( checkResult.output ).toInclude( "sample 1.0.0" );
				expect( checkResult.output ).toInclude( "settings: release.json" );
			} );

			it( "uses a local-only tag that already points to the commit", function(){
				writeTaggedReleaseProject();

				var releaseResult = runPublishDryRun();
				expectCommand( releaseResult, "the existing-tag practice run" );
				expect( releaseResult.output ).toInclude( "existing tag v1.0.0" );
				expect( releaseResult.output ).toInclude( "local only" );
				expect( releaseResult.output ).toInclude( "git push origin v1.0.0" );
				expect( releaseResult.output ).notToInclude( "git tag v1.0.0" );
				expect( fixtureProcess.runGit( originRoot, [ "tag", "--list" ] ).output ).toBe( "" );
			} );

			it( "reports when origin already has the existing tag", function(){
				writeTaggedReleaseProject();
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "push", "origin", "v1.0.0" ] ) );

				var releaseResult = runPublishDryRun();
				expectCommand( releaseResult, "the existing-tag practice run" );
				expect( releaseResult.output ).toInclude( "is on origin" );
				expect( releaseResult.output ).notToInclude( "git push origin v1.0.0" );
			} );

			it( "stops when the existing tag points to another commit on origin", function(){
				writeTaggedReleaseProject();
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "push", "origin", "v1.0.0" ] ) );
				fileWrite( fixtureRoot & "/later.txt", "a later commit" );
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "add", "." ] ) );
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "commit", "-m", "Later" ] ) );
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "-f", "v1.0.0" ] ) );

				var releaseResult = runPublishDryRun();
				expect( releaseResult.exitCode ).notToBe( 0 );
				expect( releaseResult.output ).toInclude( "different commit" );
			} );

			it( "stops when a local tag for the version points to an older commit", function(){
				writeTaggedReleaseProject();
				fileWrite( fixtureRoot & "/later.txt", "a later commit" );
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "add", "." ] ) );
				expectGit( fixtureProcess.runGit( fixtureRoot, [ "commit", "-m", "Later" ] ) );

				var releaseResult = runPublishDryRun();
				expect( releaseResult.exitCode ).notToBe( 0 );
				expect( releaseResult.output ).toInclude( "already released" );
			} );

			// This command pushes the tag to the local bare origin. The next GitHub Release step
			// fails because gh is missing or no remote uses GitHub. The command stops there and
			// does not send data outside this computer.
			it( "pushes a local-only tag before it tries to create the GitHub Release", function(){
				writeTaggedReleaseProject();
				expectCommand( runPublishDryRun(), "the practice run that builds the zip" );

				var resumeResult = fixtureProcess.runCommand( fixtureRoot, "release resume" );
				expect( resumeResult.exitCode ).notToBe( 0 );
				expect( resumeResult.output ).toInclude( "Pushed tag v1.0.0 to origin" );
				expect( resumeResult.output ).notToInclude( "git push origin master" );
				expect( fixtureProcess.runGit( originRoot, [ "tag", "--list" ] ).output ).toBe( "v1.0.0" );
			} );
		} );
	}

	private void function writeBasicProject(
		required string version,
		boolean publishGitHub = false,
		array ignore          = [],
		struct extraSettings  = {},
		string packageType    = "commandbox-modules"
	){
		var packageData = {
			"name"    : "Sample",
			"slug"    : "sample",
			"version" : arguments.version,
			"type"    : arguments.packageType
		};
		if ( arrayLen( arguments.ignore ) ) {
			packageData[ "ignore" ] = arguments.ignore;
		}
		fileWrite( fixtureRoot & "/box.json", serializeJSON( packageData ) );

		var settings = {
			"branch"           : "master",
			"changelog"        : "CHANGELOG.md",
			"testRunner"       : "http://127.0.0.1:60299/tests/runner.cfm",
			"runTests"         : false,
			"gitSync"          : true,
			"requireCleanTree" : true,
			"publish"          : { "forgebox" : false, "github" : arguments.publishGitHub },
			"engines"          : []
		};
		structAppend( settings, arguments.extraSettings, true );
		writeJSON( fixtureRoot & "/release.json", settings );
	}

	private void function writeFile( required string relative, required string content ){
		var path = fixtureRoot & "/" & arguments.relative;
		var dir  = getDirectoryFromPath( path );
		if ( !directoryExists( dir ) ) {
			directoryCreate( dir, true, true );
		}
		fileWrite( path, arguments.content );
	}

	private string function zipEntryNames( required string zipPath ){
		cfzip( action = "list", file = arguments.zipPath, name = "local.zipEntries" );
		return valueArray( local.zipEntries.name ).toList( "," );
	}

	private void function writeChangelog(
		boolean includeUnreleasedNote = false,
		string releasedVersion = ""
	){
		var lf      = chr( 10 );
		var heading = repeatString( chr( 35 ), 2 ) & " ";
		var content = heading & "[Unreleased]" & lf & lf;
		if ( arguments.includeUnreleasedNote ) {
			content &= "- Pending change" & lf & lf;
		}
		if ( len( arguments.releasedVersion ) ) {
			content &= heading & "[#arguments.releasedVersion#] - 2026-08-07" & lf & lf & "- Release notes" & lf;
		}
		fileWrite( fixtureRoot & "/CHANGELOG.md", content );
	}

	private void function writeTaggedReleaseProject(){
		writeBasicProject( "1.0.0", true );
		writeChangelog( false, "1.0.0" );
		fileWrite( fixtureRoot & "/source.txt", "release fixture" );
		createLocalGitRemote();
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "tag", "v1.0.0" ] ) );
	}

	private struct function runPublishDryRun(){
		return fixtureProcess.runCommand( fixtureRoot, "release publish --dryRun --skipTests" );
	}

	private void function createLocalGitRemote(){
		originRoot = fixtureRoot & "-origin.git";
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "init" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "symbolic-ref", "HEAD", "refs/heads/master" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "config", "user.email", "tests@example.com" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "config", "user.name", "Release Tests" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "add", "." ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "commit", "-m", "Fixture" ] ) );
		directoryCreate( originRoot, true, true );
		expectGit( fixtureProcess.runGit( originRoot, [ "init", "--bare" ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "remote", "add", "origin", originRoot ] ) );
		expectGit( fixtureProcess.runGit( fixtureRoot, [ "push", "-u", "origin", "master" ] ) );
	}

	private void function expectGit( required struct result ){
		expectCommand( arguments.result, "Git" );
	}
}
