/**
 * Reads and updates changelog text for version and release commands.
 *
 * This component only works with text strings. Other components read and write the files.
 * Tests can check every changelog rule without using the file system.
 */
component {

	/**
	 * Moves [Unreleased] notes into a dated section for one version.
	 *
	 * The result keeps the input text's line ending style.
	 *
	 * @content       The full changelog text.
	 * @version       The version for the dated section.
	 * @date          The release date in YYYY-MM-DD format.
	 * @changelogName The filename to include in error messages.
	 */
	string function moveUnreleasedNotes(
		required string content,
		required string version,
		required string date,
		string changelogName = "CHANGELOG.md"
	){
		var usesWindowsLineEndings = arguments.content contains ( chr( 13 ) & chr( 10 ) );
		var lineFeed               = chr( 10 );
		var lines                  = listToArray(
			replace( arguments.content, chr( 13 ) & lineFeed, lineFeed, "all" ),
			lineFeed,
			true
		);

		var unreleasedIndex = findUnreleasedHeading( lines );
		if ( unreleasedIndex == 0 ) {
			throw(
				type    = "Release.Changelog.MissingUnreleased",
				message = "#arguments.changelogName# does not have a ""#### [Unreleased]"" section. Add the heading, write your notes below it, and run the command again."
			);
		}

		var sectionEndIndex = findSectionEnd( lines, unreleasedIndex + 1 );
		var releaseNotes    = copyLines( lines, unreleasedIndex + 1, sectionEndIndex - 1 );
		trimBlankEdges( releaseNotes );

		if ( !arrayLen( releaseNotes ) ) {
			throw(
				type    = "Release.Changelog.EmptyUnreleased",
				message = "The ""#### [Unreleased]"" section in #arguments.changelogName# is empty. Add at least one release note first."
			);
		}

		var outputLines = copyLines( lines, 1, unreleasedIndex );
		outputLines.append( "" );
		outputLines.append( "#### [" & arguments.version & "] - " & arguments.date );
		outputLines.append( "" );
		outputLines.append( releaseNotes, true );
		outputLines.append( "" );
		outputLines.append( copyLines( lines, sectionEndIndex, arrayLen( lines ) ), true );

		var outputLineEnding = usesWindowsLineEndings ? ( chr( 13 ) & lineFeed ) : lineFeed;
		return arrayToList( outputLines, outputLineEnding );
	}

	/**
	 * Returns the notes from one dated version section.
	 *
	 * @content       The full changelog text.
	 * @version       The version to read.
	 * @changelogName The filename to include in error messages.
	 */
	string function extractReleaseNotes(
		required string content,
		required string version,
		string changelogName = "CHANGELOG.md"
	){
		var lines         = listToArray( arguments.content, chr( 10 ), true );
		var collected     = [];
		var insideSection = false;

		for ( var rawLine in lines ) {
			var line      = reReplace( rawLine, chr( 13 ) & "$", "" );
			var isHeading = reFind( "^####\s*\[", line );

			if ( !insideSection && isHeading && line contains "[#arguments.version#]" ) {
				insideSection = true;
				continue;
			}

			if ( insideSection ) {
				if ( isSectionBoundary( line ) ) {
					break;
				}
				collected.append( line );
			}
		}

		if ( !insideSection ) {
			throw(
				type    = "Release.Changelog.MissingVersion",
				message = "#arguments.changelogName# does not have a ""#### [#arguments.version#]"" section. "
					& "Move the [Unreleased] notes into a dated section with: "
					& "box release bump patch"
			);
		}

		var releaseNotes = trim( arrayToList( collected, chr( 10 ) ) );
		if ( !len( releaseNotes ) ) {
			throw(
				type    = "Release.Changelog.EmptyVersion",
				message = "The ""#### [#arguments.version#]"" section in #arguments.changelogName# is empty. Add at least one release note first."
			);
		}

		return releaseNotes;
	}

	/**
	 * Lists version headings in their original order. It leaves out [Unreleased] because that
	 * heading does not identify a version.
	 *
	 * @content The full changelog text.
	 */
	array function versionHeadings( required string content ){
		var versions = [];
		for ( var rawLine in listToArray( arguments.content, chr( 10 ), true ) ) {
			var line  = reReplace( rawLine, chr( 13 ) & "$", "" );
			var match = reFind( "^####\s*\[([^\]]+)\]", line, 1, true );
			if ( arrayLen( match.pos ) < 2 || match.pos[ 1 ] == 0 ) {
				continue;
			}
			var heading = trim( mid( line, match.pos[ 2 ], match.len[ 2 ] ) );
			if ( heading != "Unreleased" ) {
				versions.append( heading );
			}
		}
		return versions;
	}

	private numeric function findUnreleasedHeading( required array lines ){
		for ( var index = 1; index <= arrayLen( arguments.lines ); index++ ) {
			if ( reFindNoCase( "^####\s*\[Unreleased\]", arguments.lines[ index ] ) ) {
				return index;
			}
		}
		return 0;
	}

	private numeric function findSectionEnd( required array lines, required numeric startIndex ){
		for ( var index = arguments.startIndex; index <= arrayLen( arguments.lines ); index++ ) {
			if ( isSectionBoundary( arguments.lines[ index ] ) ) {
				return index;
			}
		}
		return arrayLen( arguments.lines ) + 1;
	}

	private boolean function isSectionBoundary( required string line ){
		return reFind( "^####\s", arguments.line ) || reFind( "^\[.+\]:\s*http", arguments.line );
	}

	private array function copyLines( required array lines, required numeric startIndex, required numeric endIndex ){
		var copiedLines = [];
		for ( var index = arguments.startIndex; index <= arguments.endIndex; index++ ) {
			if ( index >= 1 && index <= arrayLen( arguments.lines ) ) {
				copiedLines.append( arguments.lines[ index ] );
			}
		}
		return copiedLines;
	}

	private void function trimBlankEdges( required array lines ){
		while ( arrayLen( arguments.lines ) && !len( trim( arguments.lines[ 1 ] ) ) ) {
			arguments.lines.deleteAt( 1 );
		}
		while ( arrayLen( arguments.lines ) && !len( trim( arguments.lines[ arrayLen( arguments.lines ) ] ) ) ) {
			arguments.lines.deleteAt( arrayLen( arguments.lines ) );
		}
	}
}
