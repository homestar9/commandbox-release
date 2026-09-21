/**
 * Changes the project version and prepares its changelog for a release.
 *
 * `box release bump patch`, `minor`, or `major` changes the version in box.json. It moves the
 * [Unreleased] notes into a dated section for that version.
 *
 * It does not commit, tag, or publish. Use `--dryRun` to view the file changes without writing
 * them. Use `none` when the first release already has the correct version.
 * `box release publish <level>` uses this same component before it commits and publishes.
 */
component extends="commandbox-release.models.BaseService" {

	property name="versionService"   inject="VersionService@commandbox-release";
	property name="changelogService" inject="ChangelogService@commandbox-release";

	/**
	 * Calculates the box.json and changelog changes before writing either file. It returns the
	 * new version.
	 *
	 * @level  The version change: major, minor, patch, prerelease, premajor, preminor, prepatch,
	 *         or none.
	 * @preid  The prerelease label, such as beta or alpha. New prereleases use beta by default.
	 * @dryRun Shows the changes without writing any files.
	 * @allowPrereleaseRetarget Allows preminor to change the target of an active prerelease.
	 * @quiet  Leaves out the manual next steps. The publish command prints its own.
	 */
	string function run(
		string level = "patch",
		string preid = "",
		boolean dryRun = false,
		boolean allowPrereleaseRetarget = false,
		boolean quiet = false
	){
		var requestedLevel = ensureLevel( arguments.level );

		var currentVersion = variables.config.version();
		var currentParts   = variables.versionService.parseVersion( currentVersion );
		if (
			requestedLevel == "preminor"
			&& len( currentParts.prerelease )
			&& !arguments.allowPrereleaseRetarget
		) {
			return fail(
				"#currentVersion# is already a prerelease. preminor cannot change its target without permission.",
				[
					"box release bump prerelease                           update the current prerelease",
					"box release bump preminor --allowPrereleaseRetarget   target the next minor version"
				],
				"Choose a prerelease action"
			);
		}
		var newVersion   = currentVersion;
		var releaseDate  = dateFormat( now(), "yyyy-mm-dd" );
		var newChangelog = "";

		try {
			if ( requestedLevel != "none" ) {
				newVersion = variables.versionService.nextVersion(
					currentVersion,
					requestedLevel,
					trim( arguments.preid )
				);
			}

			// Build the full changelog before changing either file. A missing or empty
			// [Unreleased] section can then stop the command without leaving a partial update.
			newChangelog = buildChangelog( newVersion, releaseDate );
		} catch ( any exception ) {
			if ( exception.type == "Release.Version.NotPrerelease" ) {
				return fail(
					exception.message,
					[
						"box release bump preminor beta     start the next minor version as beta",
						"box release bump preminor alpha    start the next minor version as alpha",
						"box release bump prepatch          start the next patch version",
						"box release bump premajor          start the next major version"
					],
					"Start a prerelease"
				);
			}
			return stop( exception.message );
		}

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "Practice run: no files were changed." )
				.line( "Version:   #currentVersion# -> #newVersion#" )
				.line( "Changelog: the notes would move to #### [#newVersion#] - #releaseDate#" )
				.line()
				.boldLine( "The updated changelog would begin with:" )
				.line( left( newChangelog, 600 ) )
				.toConsole();
			return newVersion;
		}

		if ( newVersion != currentVersion ) {
			setBoxVersion( newVersion );
			print.greenLine( "box.json: #currentVersion# -> #newVersion#" ).toConsole();
		} else {
			print.greenLine( "box.json stays at #currentVersion# (level none)." ).toConsole();
		}

		fileWrite( variables.config.repoPath( variables.settings.changelog ), newChangelog );
		print.greenLine( "#variables.settings.changelog#: moved the notes to #### [#newVersion#] - #releaseDate#" ).toConsole();

		if ( !arguments.quiet ) {
			print
				.line()
				.boldMagentaLine( "Version #newVersion# is ready. Next steps:" )
				.line( "  1. Review:   git diff -- box.json ""#variables.settings.changelog#""" )
				.line( "  2. Commit:   git add box.json ""#variables.settings.changelog#""" )
				.line( "               git commit -m ""Release #newVersion#""" )
				.line( "  3. Check:    box release check" )
				.line( "  4. Publish:  box release publish" )
				.line()
				.line( "Next time, box release publish #requestedLevel# does all of these steps in one command." )
				.toConsole();
		}
		return newVersion;
	}

	/**
	 * Returns the level in lower case. It stops with the list of valid levels when the level is
	 * unknown.
	 *
	 * @level The requested level.
	 */
	string function ensureLevel( required string level ){
		var requestedLevel = lCase( trim( arguments.level ) );
		if ( !listFindNoCase( variables.versionService.supportedLevels(), requestedLevel ) ) {
			return fail(
				"Unknown level '#arguments.level#'.",
				[
					"major, minor, patch            change a normal version. For a prerelease, these",
					"                               finish the version that the prerelease targets.",
					"prerelease                     update a prerelease, such as beta.3 to beta.4.",
					"premajor, preminor, prepatch   start a prerelease. The default label is beta.",
					"none                           keep the version and date the changelog."
				],
				"Valid version levels"
			);
		}
		return requestedLevel;
	}

	// PRIVATE HELPERS

	/**
	 * Changes only the version value in box.json. All other formatting stays unchanged.
	 */
	private function setBoxVersion( required string version ){
		var boxPath     = variables.config.repoPath( "box.json" );
		var packageText = fileRead( boxPath );

		// Find the first "version":"..." value and replace only the text inside its quotes.
		// Do not use a regular expression replacement such as "\1" here. A version that starts
		// with a digit could make the replacement look like a different capture group number.
		var versionMatch = reFind( '("version"\s*:\s*")([^"]*)(")', packageText, 1, true );
		if ( !arrayLen( versionMatch.pos ) || versionMatch.pos[ 1 ] == 0 ) {
			return stop( "box.json does not contain a ""version"" entry." );
		}
		var valueStart  = versionMatch.pos[ 3 ];
		var valueLength = versionMatch.len[ 3 ];
		fileWrite(
			boxPath,
			left( packageText, valueStart - 1 )
				& arguments.version
				& mid( packageText, valueStart + valueLength, len( packageText ) )
		);
	}

	/**
	 * Reads the changelog and returns the updated text from ChangelogService.
	 */
	private string function buildChangelog( required string version, required string date ){
		var changelogPath = variables.config.repoPath( variables.settings.changelog );
		if ( !fileExists( changelogPath ) ) {
			throw(
				type    = "Release.Changelog.MissingFile",
				message = "The project root does not contain #variables.settings.changelog#. "
					& "Create it with a ""#### [Unreleased]"" section, or run: box release init"
			);
		}

		return variables.changelogService.moveUnreleasedNotes(
			content       = fileRead( changelogPath ),
			version       = arguments.version,
			date          = arguments.date,
			changelogName = variables.settings.changelog
		);
	}
}
