/**
 * Builds and checks a package before publishing.
 *
 * `box release package` runs tests and copies package files to an empty temporary folder.
 * It fills in version values, creates a zip, checks the zip, and writes checksum files.
 *
 * The box.json ignore list decides which project files stay out. ForgeBox uses the same list.
 * This keeps the GitHub zip and ForgeBox package in sync.
 *
 * It writes build files under .artifacts/<slug>/<version>/. Use `--skipTests` only when the
 * same source code already passed the tests. Project settings come from release.json.
 */
component extends="commandbox-release.models.BaseService" {

	/**
	 * Stores the project and its temporary and artifact folder paths. It does not change either
	 * folder until the first build step runs.
	 */
	function forProject( required any config ){
		super.forProject( arguments.config );
		variables.stagingRoot  = variables.root & "/" & variables.settings.stagingDir;
		variables.artifactsDir = variables.root & "/" & variables.settings.artifactsDir;
		variables.prepared     = false;
		return this;
	}

	/**
	 * Runs tests, builds the package, and writes checksum files.
	 *
	 * @projectName The package folder and zip filename. The default is the box.json slug.
	 * @version     The version to build. The default is the box.json version.
	 * @buildID     The build ID. The default is the short Git commit hash.
	 * @branch      The branch to build. The default is the current branch.
	 * @skipTests   Skips tests for this run and prints a warning. Use it only after this version
	 *              has passed its tests.
	 */
	function run(
		string projectName = "",
		string version     = "",
		string buildID     = "",
		string branch      = "",
		boolean skipTests  = false
	){
		prepare();
		fillDefaults( arguments );

		if ( arguments.skipTests || !variables.settings.runTests ) {
			var reason = arguments.skipTests ? "requested with skipTests" : "disabled in release.json";
			print
				.line()
				.boldYellowLine( "WARNING: This build skipped the tests (#reason#)." )
				.yellowLine( "This build did not test the package." )
				.line()
				.toConsole();
		} else {
			service( "TestRunner" ).runOnce();
		}

		// Add a mapping so build steps can load components from the project.
		variables.fileSystemUtil.createMapping( arguments.projectName, variables.root );

		buildSource( argumentCollection = arguments );
		buildChecksums();

		print.line().boldMagentaLine( "Build complete. Package files are in #variables.exportsDir#" ).toConsole();
	}

	/**
	 * Creates and checks the source package without running tests.
	 *
	 * @projectName The package folder and zip filename.
	 * @version     The version to build.
	 * @buildID     The build ID.
	 * @branch      The branch to build.
	 * @skipTests   Allows this function to accept the same arguments as run().
	 */
	function buildSource(
		string projectName = "",
		string version     = "",
		string buildID     = "",
		string branch      = "",
		boolean skipTests  = false
	){
		prepare();
		fillDefaults( arguments );

		print
			.line()
			.boldMagentaLine(
				"Building #arguments.projectName# #arguments.version#+#arguments.buildID# from branch #arguments.branch#."
			)
			.toConsole();

		ensureExportDir( arguments.projectName, arguments.version );

		variables.projectBuildDir = variables.stagingRoot & "/#arguments.projectName#";
		directoryCreate( variables.projectBuildDir, true, true );

		copySourceToStaging();
		verifyStaging();
		writeBuildMarker( argumentCollection = arguments );
		replaceBuildTokens( argumentCollection = arguments );

		var zipPath = createPackageZip( arguments.projectName, arguments.version );
		verifyZip( zipPath );
		copyPackageManifest();
	}

	/**
	 * Returns the patterns used to leave files out of the package. The module always leaves
	 * out Git data, its temporary and artifact folders, and release.json. It also uses the
	 * ignore list in box.json.
	 *
	 * Never copy .gitignore. CommandBox reads .gitignore in the folder it publishes. If we
	 * copied that file, ForgeBox could leave out files that are still in the GitHub zip. We also
	 * do not use the project's .gitignore to choose package files.
	 */
	array function ignorePatterns(){
		var patterns = [
			".git/",
			".gitignore",
			".npmignore",
			"/release.json",
			".*.swp",
			"._*",
			".DS_Store",
			".hg/",
			".svn/"
		];
		for ( var folder in [ variables.settings.stagingDir, variables.settings.artifactsDir ] ) {
			var cleanFolder = reReplace( replace( folder, "\", "/", "all" ), "^/+|/+$", "", "all" );
			if ( len( cleanFolder ) ) {
				patterns.append( "/" & cleanFolder & "/" );
			}
		}
		patterns.append( variables.config.packageIgnores(), true );
		return patterns;
	}

	// BUILD STEPS

	/** Empties and creates the temporary and artifact folders once for each build. */
	private void function prepare(){
		if ( variables.prepared ) {
			return;
		}
		for ( var directoryPath in [ variables.stagingRoot, variables.artifactsDir ] ) {
			if ( directoryExists( directoryPath ) ) {
				directoryDelete( directoryPath, true );
			}
			directoryCreate( directoryPath, true, true );
		}
		configureColdBoxMapping();
		variables.prepared = true;
	}

	private void function configureColdBoxMapping(){
		if ( !len( trim( variables.settings.coldboxMapping ) ) ) {
			return;
		}

		var coldboxPath = variables.root & "/" & variables.settings.coldboxMapping;
		if ( directoryExists( coldboxPath ) ) {
			variables.fileSystemUtil.createMapping( "coldbox", coldboxPath );
		}
	}

	private void function copySourceToStaging(){
		print.blueLine( "Copying the shipped files to the temporary build folder..." ).toConsole();
		copy( variables.root, variables.projectBuildDir );
	}

	private void function writeBuildMarker(
		required string projectName,
		required string version,
		required string buildID
	){
		fileWrite(
			"#variables.projectBuildDir#/#arguments.projectName#-#arguments.version#+#arguments.buildID#",
			"Built from commit #arguments.buildID# at #dateTimeFormat( now(), "full" )#"
		);
	}

	private void function replaceBuildTokens(
		required string version,
		required string buildID,
		required string branch
	){
		print.greenLine( "Adding version #arguments.version#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "#variables.projectBuildDir#/**",
				token       = "@build.version@",
				replacement = arguments.version
			)
			.run();

		var isReleaseBranch = arguments.branch == variables.settings.branch;
		print.greenLine( "Adding build ID #arguments.buildID#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "#variables.projectBuildDir#/**",
				token       = isReleaseBranch ? "@build.number@" : "+@build.number@",
				replacement = isReleaseBranch ? arguments.buildID : "-snapshot"
			)
			.run();
	}

	private string function createPackageZip( required string projectName, required string version ){
		var zipPath = "#variables.exportsDir#/#arguments.projectName#-#arguments.version#.zip";
		print.greenLine( "Creating zip file #zipPath#" ).toConsole();
		cfzip(
			action    = "zip",
			file      = zipPath,
			source    = variables.projectBuildDir,
			overwrite = true,
			recurse   = true
		);
		return zipPath;
	}

	private void function copyPackageManifest(){
		// Copy box.json next to the zip so people can read package details without opening it.
		fileCopy( "#variables.projectBuildDir#/box.json", variables.exportsDir );
	}

	// SHARED HELPERS

	/**
	 * Fills blank arguments with project values. The slug and version come from box.json. The
	 * branch and commit come from Git. Both public entry points use these same defaults.
	 */
	private void function fillDefaults( required struct args ){
		if ( !len( trim( arguments.args.projectName ?: "" ) ) ) {
			arguments.args.projectName = variables.config.slug();
		}
		if ( !len( trim( arguments.args.version ?: "" ) ) ) {
			arguments.args.version = variables.config.version();
		}
		if ( !len( trim( arguments.args.branch ?: "" ) ) ) {
			arguments.args.branch = getCurrentBranch();
		}
		if ( !len( trim( arguments.args.buildID ?: "" ) ) ) {
			arguments.args.buildID = getCurrentCommit();
		}
	}

	/**
	 * Returns the current branch. It returns the release branch from release.json for a detached
	 * checkout, or when Git cannot read the folder, such as a source copy without Git data.
	 */
	private string function getCurrentBranch(){
		try {
			var branch = repository().currentBranch();
			return branch == "HEAD" ? variables.settings.branch : branch;
		} catch ( "Release.Git" exception ) {
			return variables.settings.branch;
		}
	}

	/**
	 * Returns the short commit hash. It returns "nocommit" when Git cannot read a commit.
	 */
	private string function getCurrentCommit(){
		try {
			return left( repository().headCommit(), 7 );
		} catch ( "Release.Git" exception ) {
			return "nocommit";
		}
	}

	/**
	 * Writes SHA-512 and MD5 files next to the zip. These checksums can show whether a download
	 * changed or became damaged.
	 */
	private function buildChecksums(){
		print.greenLine( "Writing checksum files" ).toConsole();
		command( "checksum" )
			.params(
				path      = "#variables.exportsDir#/*.zip",
				algorithm = "SHA-512",
				extension = "sha512",
				write     = true
			)
			.run();
		command( "checksum" )
			.params(
				path      = "#variables.exportsDir#/*.zip",
				algorithm = "md5",
				extension = "md5",
				write     = true
			)
			.run();
	}

	/**
	 * Stops when a box.json ignore rule leaves out a required file. This check runs before
	 * publishing.
	 */
	private function verifyStaging(){
		var missing = [];
		if ( !fileExists( variables.projectBuildDir & "/box.json" ) ) {
			missing.append( "box.json" );
		}
		if (
			fileExists( variables.root & "/ModuleConfig.cfc" )
			&& !fileExists( variables.projectBuildDir & "/ModuleConfig.cfc" )
		) {
			missing.append( "ModuleConfig.cfc" );
		}
		if ( arrayLen( missing ) ) {
			return stop(
				"The package is missing #arrayToList( missing, ", " )#. The box.json ignore list excludes a required file. "
				& "Remove that pattern from the ignore list, then build again."
			);
		}
		if ( fileExists( variables.projectBuildDir & "/.gitignore" ) ) {
			return stop( "The temporary build folder contains .gitignore. This is a commandbox-release bug because .gitignore must stay out of the package." );
		}
	}

	/**
	 * Stops the build when the zip and temporary folder contain different numbers of files.
	 *
	 * This check counts files but does not identify the missing file. It catches any rule that
	 * removes source files from the zip after they were staged.
	 */
	private function verifyZip( required string zipPath ){
		cfzip( action = "list", file = arguments.zipPath, name = "local.zipEntries" );

		var stagedCount = directoryList( variables.projectBuildDir, true, "path" )
			.filter( function( item ){
				return fileExists( item );
			} )
			.len();

		// A zip also lists folder entries. Count only file entries.
		var zippedCount = 0;
		for ( var row in local.zipEntries ) {
			if ( row.type == "file" ) {
				zippedCount++;
			}
		}

		if ( zippedCount != stagedCount ) {
			return stop(
				"The zip is incomplete. The temporary folder has #stagedCount# files, but the zip has #zippedCount#. "
				& "Temporary folder: #variables.projectBuildDir#"
			);
		}

		print.greenLine( "Zip check passed. It contains all #zippedCount# temporary files." ).toConsole();
	}

	/**
	 * Copies files to the temporary folder unless ignorePatterns() excludes them. CommandBox's
	 * globber matches paths with the same rules ForgeBox uses for box.json ignore. This function
	 * copies the files itself so it can list them. It also compares Windows drive letters
	 * without case, since a different letter case would break the relative paths.
	 */
	private function copy( required string src, required string target ){
		var sourceRoot = replace( arguments.src, "\", "/", "all" );
		sourceRoot     = reReplace( sourceRoot, "/+$", "" ) & "/";
		var targetRoot = reReplace( replace( arguments.target, "\", "/", "all" ), "/+$", "" ) & "/";

		var matches = variables.wirebox.getInstance( "globber" )
			.inDirectory( sourceRoot )
			.setExcludePattern( ignorePatterns() )
			.loose()
			.asQuery()
			.matches();

		var topLevel = {};
		var folders  = [];
		var files    = [];

		for ( var index = 1; index <= matches.recordCount; index++ ) {
			var directory = reReplace( replace( matches.directory[ index ], "\", "/", "all" ), "/+$", "" );
			var fullPath  = directory & "/" & matches.name[ index ];
			if ( compareNoCase( left( fullPath, len( sourceRoot ) ), sourceRoot ) != 0 ) {
				return stop( "The build could not map #fullPath# inside #sourceRoot#. The temporary folder was not filled." );
			}
			var relative = mid( fullPath, len( sourceRoot ) + 1, len( fullPath ) );
			if ( !len( relative ) ) {
				continue;
			}
			var isFolder = lCase( matches.type[ index ] ) == "dir";
			if ( isFolder ) {
				folders.append( relative );
			} else {
				files.append( { "source" : fullPath, "relative" : relative } );
			}
			var first = listFirst( relative, "/" );
			if ( !structKeyExists( topLevel, first ) ) {
				topLevel[ first ] = isFolder || find( "/", relative ) ? "folder" : "file";
			}
		}

		// Create folders first to keep empty folders and give every copied file a destination.
		folders.sort( "textnocase" );
		for ( var folder in folders ) {
			directoryCreate( targetRoot & folder, true, true );
		}
		for ( var file in files ) {
			var destination = targetRoot & file.relative;
			var parent      = getDirectoryFromPath( destination );
			if ( !directoryExists( parent ) ) {
				directoryCreate( parent, true, true );
			}
			fileCopy( file.source, destination );
		}

		var names = structKeyArray( topLevel );
		names.sort( "textnocase" );
		for ( var name in names ) {
			if ( topLevel[ name ] == "folder" ) {
				print.greenLine( "  copy folder #name#/" ).toConsole();
			} else {
				print.blueLine( "  copy #name#" ).toConsole();
			}
		}
	}

	/**
	 * Creates .artifacts/<name>/<version>/ and stores its path for the current build.
	 */
	private function ensureExportDir( required string projectName, required string version ){
		if ( structKeyExists( variables, "exportsDir" ) && directoryExists( variables.exportsDir ) ) {
			return;
		}
		variables.exportsDir = variables.artifactsDir & "/#arguments.projectName#/#arguments.version#";
		directoryCreate( variables.exportsDir, true, true );
	}
}
