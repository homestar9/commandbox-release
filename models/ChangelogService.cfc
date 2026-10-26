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
			// A group heading such as "## Added" ends the section because "##" starts a version.
			if ( sectionEndIndex <= arrayLen( lines ) ) {
				var endLine = trim( lines[ sectionEndIndex ] );
				if ( reFind( "^####\s", endLine ) && !reFind( "^####\s*\[", endLine ) ) {
					var groupName = trim( reReplace( endLine, "^####\s*", "" ) );
					throw(
						type    = "Release.Changelog.EmptyUnreleased",
						message = "The ""#### [Unreleased]"" section in #arguments.changelogName# ends at ""#endLine#"". "
							& "Use ""###### #groupName#"" for groups inside a version. ""####"" starts a new version section."
					);
				}
			}
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

	/**
	 * Combines the changelogs from both sides of a merge. The base is the changelog where both
	 * branches started. It compares these parts: the text above [Unreleased], the [Unreleased]
	 * notes, each version section, and each link reference at the end of the file. A part that
	 * changed on one branch only comes from that branch. New version sections from the merged
	 * branch keep their order. The result uses the line endings of the ours text.
	 *
	 * It throws Release.Changelog.MergeConflict when a part changed on both branches or a
	 * changelog cannot be read. The message names the part.
	 *
	 * @base          The changelog where both branches started. Empty when the file did not exist.
	 * @ours          The changelog on the branch that receives the merge.
	 * @theirs        The changelog on the branch being merged.
	 * @changelogName The filename to include in error messages.
	 */
	string function mergeChangelogs(
		required string base,
		required string ours,
		required string theirs,
		string changelogName = "CHANGELOG.md"
	){
		var oursText    = normalizeLines( arguments.ours );
		var oursParts   = parseChangelog( oursText.lines, arguments.changelogName );
		var theirsParts = parseChangelog( normalizeLines( arguments.theirs ).lines, arguments.changelogName );
		var baseParts   = len( trim( arguments.base ) )
			? parseChangelog( normalizeLines( arguments.base ).lines, arguments.changelogName )
			: absentChangelog();

		var outputLines = [];
		appendBlock(
			outputLines,
			pickBlock( "The text above [Unreleased]", baseParts.header, oursParts.header, theirsParts.header, arguments.changelogName )
		);
		appendBlock( outputLines, presentBlock( [ oursParts.unreleasedHeading ] ) );
		appendBlock(
			outputLines,
			pickBlock( "The [Unreleased] notes", baseParts.unreleased, oursParts.unreleased, theirsParts.unreleased, arguments.changelogName )
		);
		for ( var section in mergeKeyed( baseParts.sections, oursParts.sections, theirsParts.sections, "section", arguments.changelogName ) ) {
			appendBlock( outputLines, section );
		}

		var links = mergeKeyed( baseParts.links, oursParts.links, theirsParts.links, "link", arguments.changelogName );
		if ( arrayLen( links ) ) {
			outputLines.append( "" );
			for ( var link in links ) {
				outputLines.append( link.lines, true );
			}
		}

		var lineEnding = oursText.crlf ? ( chr( 13 ) & chr( 10 ) ) : chr( 10 );
		return arrayToList( outputLines, lineEnding ) & ( oursText.finalNewline ? lineEnding : "" );
	}

	/**
	 * Returns the [Unreleased] notes that also appear in the listed version sections. Each note
	 * is a bullet line without its bullet. The caller warns about them after a merge.
	 *
	 * @content  The full changelog text.
	 * @versions The versions to compare with, such as [ "1.0.1" ].
	 */
	array function repeatedNotes( required string content, required array versions ){
		var parts    = parseChangelog( normalizeLines( arguments.content ).lines );
		var released = [];
		for ( var section in parts.sections ) {
			if ( arrayFindNoCase( arguments.versions, section.key ) ) {
				released.append( bulletNotes( section.lines ), true );
			}
		}

		var repeated = [];
		for ( var note in bulletNotes( parts.unreleased.lines ) ) {
			if ( arrayFind( released, note ) && !arrayFind( repeated, note ) ) {
				repeated.append( note );
			}
		}
		return repeated;
	}

	/**
	 * Prepares a merge in which the merged branch released notes that were already under
	 * [Unreleased] where both branches started. A GitKraken Finish before the version change
	 * leaves develop in this state, and so does a branch that releases notes while develop adds
	 * more. Both branches changed [Unreleased], so mergeChangelogs() alone would stop.
	 *
	 * This removes the released notes from [Unreleased] in base and ours, and it drops group
	 * headings that have no notes left. Pass the results to mergeChangelogs(). The notes the
	 * receiving branch added stay under [Unreleased].
	 *
	 * Returns { base, ours, notes }. notes lists the removed notes. It is empty, and base and
	 * ours are unchanged, when no released note was pending at the base, when ours did not change
	 * [Unreleased], or when a changelog cannot be read. Git merges those cases correctly, or
	 * mergeChangelogs() reports them.
	 *
	 * @base          The changelog where both branches started.
	 * @ours          The changelog on the branch that receives the merge.
	 * @theirs        The changelog on the branch being merged.
	 * @changelogName The filename to include in error messages.
	 */
	struct function withoutReleasedNotes(
		required string base,
		required string ours,
		required string theirs,
		string changelogName = "CHANGELOG.md"
	){
		var result      = { "base" : arguments.base, "ours" : arguments.ours, "notes" : [] };
		var baseText    = normalizeLines( arguments.base );
		var oursText    = normalizeLines( arguments.ours );
		var baseParts   = {};
		var oursParts   = {};
		var theirsParts = {};
		try {
			baseParts   = parseChangelog( baseText.lines, arguments.changelogName );
			oursParts   = parseChangelog( oursText.lines, arguments.changelogName );
			theirsParts = parseChangelog( normalizeLines( arguments.theirs ).lines, arguments.changelogName );
		} catch ( "Release.Changelog.MergeConflict" ignoredException ) {
			return result;
		}
		if ( sameBlock( baseParts.unreleased, oursParts.unreleased ) ) {
			return result;
		}

		var oursByKey = indexByKey( oursParts.sections );
		var released  = [];
		for ( var section in theirsParts.sections ) {
			if ( !structKeyExists( oursByKey, section.key ) ) {
				for ( var item in noteItems( section.lines ) ) {
					released.append( item.text );
				}
			}
		}
		for ( var item in noteItems( baseParts.unreleased.lines ) ) {
			if ( arrayFind( released, item.text ) && !arrayFind( result.notes, item.text ) ) {
				result.notes.append( item.text );
			}
		}
		if ( !arrayLen( result.notes ) ) {
			return result;
		}

		result.base = removeUnreleasedNotes( baseText, result.notes );
		result.ours = removeUnreleasedNotes( oursText, result.notes );
		return result;
	}

	// MERGE HELPERS

	/** Splits text into lines and records its line ending style and whether it ends with a newline. */
	private struct function normalizeLines( required string text ){
		var lineFeed = chr( 10 );
		var crlf     = arguments.text contains ( chr( 13 ) & lineFeed );
		var unix     = replace( arguments.text, chr( 13 ) & lineFeed, lineFeed, "all" );
		var lines    = listToArray( unix, lineFeed, true );
		var ended    = len( unix ) && right( unix, 1 ) == lineFeed;
		if ( ended && arrayLen( lines ) ) {
			lines.deleteAt( arrayLen( lines ) );
		}
		return { "lines" : lines, "crlf" : crlf, "finalNewline" : ended };
	}

	/**
	 * Splits changelog lines into the parts that the merge compares. Each part is a block with
	 * present = true and its lines. Sections and links also have a key: the version or label in
	 * brackets. Throws Release.Changelog.MergeConflict when [Unreleased] is missing or a key
	 * appears twice.
	 */
	private struct function parseChangelog( required array lines, string changelogName = "CHANGELOG.md" ){
		var lineCount   = arrayLen( arguments.lines );
		var footerStart = lineCount + 1;
		while ( footerStart > 1 && ( !len( trim( arguments.lines[ footerStart - 1 ] ) ) || isLinkReference( arguments.lines[ footerStart - 1 ] ) ) ) {
			footerStart--;
		}

		var parts = {
			"header"            : presentBlock( [] ),
			"unreleasedHeading" : "",
			"unreleased"        : presentBlock( [] ),
			"sections"          : [],
			"links"             : []
		};
		for ( var index = footerStart; index <= lineCount; index++ ) {
			if ( isLinkReference( arguments.lines[ index ] ) ) {
				var label = bracketText( arguments.lines[ index ] );
				requireNewKey( parts.links, label, "link", arguments.changelogName );
				parts.links.append( keyedBlock( label, [ arguments.lines[ index ] ] ) );
			}
		}

		var body            = copyLines( arguments.lines, 1, footerStart - 1 );
		var unreleasedIndex = findUnreleasedHeading( body );
		if ( unreleasedIndex == 0 ) {
			throw(
				type    = "Release.Changelog.MergeConflict",
				message = "#arguments.changelogName# does not have a ""#### [Unreleased]"" section on one of the branches."
			);
		}
		parts.header            = presentBlock( copyLines( body, 1, unreleasedIndex - 1 ) );
		parts.unreleasedHeading = body[ unreleasedIndex ];

		var current = parts.unreleased;
		for ( var bodyIndex = unreleasedIndex + 1; bodyIndex <= arrayLen( body ); bodyIndex++ ) {
			var line = body[ bodyIndex ];
			if ( isSectionStart( line ) ) {
				var key = bracketText( line );
				if ( !len( key ) ) {
					key = trim( reReplace( line, "^####\s*", "" ) );
				}
				requireNewKey( parts.sections, key, "section", arguments.changelogName );
				current = keyedBlock( key, [ line ] );
				parts.sections.append( current );
				continue;
			}
			current.lines.append( line );
		}
		return parts;
	}

	/** Returns the parts of a changelog that did not exist. Every block is absent. */
	private struct function absentChangelog(){
		return {
			"header"            : absentBlock(),
			"unreleasedHeading" : "",
			"unreleased"        : absentBlock(),
			"sections"          : [],
			"links"             : []
		};
	}

	/**
	 * Chooses one version of a part. Both sides equal: keep it. One side equal to the base: the
	 * other side changed it, so take the other side. A side without the part removed or never
	 * had it. Anything else is a conflict.
	 */
	private struct function pickBlock(
		required string label,
		required struct base,
		required struct ours,
		required struct theirs,
		required string changelogName
	){
		if ( arguments.ours.present && arguments.theirs.present ) {
			if ( sameBlock( arguments.ours, arguments.theirs ) ) {
				return arguments.ours;
			}
			if ( arguments.base.present && sameBlock( arguments.theirs, arguments.base ) ) {
				return arguments.ours;
			}
			if ( arguments.base.present && sameBlock( arguments.ours, arguments.base ) ) {
				return arguments.theirs;
			}
			throw(
				type    = "Release.Changelog.MergeConflict",
				message = "#arguments.label# in #arguments.changelogName# changed on both branches."
			);
		}

		var kept = arguments.ours.present ? arguments.ours : arguments.theirs;
		if ( !kept.present || !arguments.base.present ) {
			// Added on one branch, or missing everywhere.
			return kept;
		}
		if ( sameBlock( kept, arguments.base ) ) {
			// Removed on the other branch and unchanged here.
			return absentBlock();
		}
		throw(
			type    = "Release.Changelog.MergeConflict",
			message = "#arguments.label# in #arguments.changelogName# was removed on one branch and changed on the other."
		);
	}

	/**
	 * Combines keyed blocks, such as version sections. Ours keeps its order. A block that only
	 * theirs has goes before the next theirs block that ours also has, or at the end.
	 */
	private array function mergeKeyed(
		required array base,
		required array ours,
		required array theirs,
		required string kind,
		required string changelogName
	){
		var baseByKey   = indexByKey( arguments.base );
		var oursByKey   = indexByKey( arguments.ours );
		var theirsByKey = indexByKey( arguments.theirs );

		var order = [];
		for ( var block in arguments.ours ) {
			order.append( block.key );
		}
		for ( var index = 1; index <= arrayLen( arguments.theirs ); index++ ) {
			var key = arguments.theirs[ index ].key;
			if ( structKeyExists( oursByKey, key ) ) {
				continue;
			}
			var anchor = 0;
			for ( var later = index + 1; later <= arrayLen( arguments.theirs ); later++ ) {
				if ( structKeyExists( oursByKey, arguments.theirs[ later ].key ) ) {
					anchor = arrayFindNoCase( order, arguments.theirs[ later ].key );
					break;
				}
			}
			if ( anchor ) {
				order.insertAt( anchor, key );
			} else {
				order.append( key );
			}
		}

		var merged = [];
		for ( var key in order ) {
			var label  = "The [#key#] #arguments.kind#";
			var picked = pickBlock(
				label,
				baseByKey[ key ] ?: absentBlock(),
				oursByKey[ key ] ?: absentBlock(),
				theirsByKey[ key ] ?: absentBlock(),
				arguments.changelogName
			);
			if ( picked.present ) {
				merged.append( picked );
			}
		}
		return merged;
	}

	/** Returns true when two blocks have the same lines, ignoring whitespace differences and blank edges. */
	private boolean function sameBlock( required struct first, required struct second ){
		var firstLines  = comparableLines( arguments.first.lines );
		var secondLines = comparableLines( arguments.second.lines );
		if ( arrayLen( firstLines ) != arrayLen( secondLines ) ) {
			return false;
		}
		for ( var index = 1; index <= arrayLen( firstLines ); index++ ) {
			if ( compare( firstLines[ index ], secondLines[ index ] ) != 0 ) {
				return false;
			}
		}
		return true;
	}

	private array function comparableLines( required array lines ){
		var result = [];
		for ( var line in arguments.lines ) {
			result.append( trim( reReplace( line, "\s+", " ", "all" ) ) );
		}
		trimBlankEdges( result );
		return result;
	}

	/** Adds a block's lines after a blank line. Blank lines at the block's edges are left out. */
	private void function appendBlock( required array outputLines, required struct block ){
		if ( !arguments.block.present ) {
			return;
		}
		var lines = duplicate( arguments.block.lines );
		trimBlankEdges( lines );
		if ( !arrayLen( lines ) ) {
			return;
		}
		if ( arrayLen( arguments.outputLines ) ) {
			arguments.outputLines.append( "" );
		}
		arguments.outputLines.append( lines, true );
	}

	private struct function presentBlock( required array lines ){
		return { "present" : true, "lines" : arguments.lines };
	}

	private struct function absentBlock(){
		return { "present" : false, "lines" : [] };
	}

	private struct function keyedBlock( required string key, required array lines ){
		return { "present" : true, "key" : arguments.key, "lines" : arguments.lines };
	}

	private struct function indexByKey( required array blocks ){
		var byKey = {};
		for ( var block in arguments.blocks ) {
			byKey[ block.key ] = block;
		}
		return byKey;
	}

	private void function requireNewKey(
		required array blocks,
		required string key,
		required string kind,
		required string changelogName
	){
		for ( var block in arguments.blocks ) {
			if ( compareNoCase( block.key, arguments.key ) == 0 ) {
				throw(
					type    = "Release.Changelog.MergeConflict",
					message = "The [#arguments.key#] #arguments.kind# appears twice in #arguments.changelogName# on one of the branches."
				);
			}
		}
	}

	/** Returns the bullet notes in the lines without their bullets. */
	private array function bulletNotes( required array lines ){
		var notes = [];
		for ( var line in arguments.lines ) {
			if ( reFind( "^\s*[-*]\s+\S", line ) ) {
				notes.append( trim( reReplace( line, "^\s*[-*]\s+", "" ) ) );
			}
		}
		return notes;
	}

	/**
	 * Returns the bullet notes in the lines as { start, end, text }. A note includes the indented
	 * lines that continue it. The text joins its lines without the bullet and with single spaces.
	 */
	private array function noteItems( required array lines ){
		var items  = [];
		var inNote = false;
		for ( var index = 1; index <= arrayLen( arguments.lines ); index++ ) {
			var line = arguments.lines[ index ];
			if ( reFind( "^\s*[-*]\s+\S", line ) ) {
				items.append( { "start" : index, "end" : index, "text" : trim( reReplace( line, "^\s*[-*]\s+", "" ) ) } );
				inNote = true;
			} else if ( inNote && len( trim( line ) ) && reFind( "^\s", line ) ) {
				items[ arrayLen( items ) ].end = index;
				items[ arrayLen( items ) ].text &= " " & trim( line );
			} else {
				inNote = false;
			}
		}
		for ( var item in items ) {
			item.text = reReplace( item.text, "\s+", " ", "all" );
		}
		return items;
	}

	/**
	 * Removes the listed notes from the [Unreleased] section and returns the changelog text. It
	 * also removes group headings left without notes and repeated blank lines. The text keeps its
	 * line endings and final newline.
	 *
	 * @text  The changelog from normalizeLines().
	 * @notes The note texts from noteItems() to remove.
	 */
	private string function removeUnreleasedNotes( required struct text, required array notes ){
		var lines       = arguments.text.lines;
		var footerStart = arrayLen( lines ) + 1;
		while ( footerStart > 1 && ( !len( trim( lines[ footerStart - 1 ] ) ) || isLinkReference( lines[ footerStart - 1 ] ) ) ) {
			footerStart--;
		}
		var unreleasedIndex = findUnreleasedHeading( lines );
		var sectionEnd      = unreleasedIndex + 1;
		while ( sectionEnd < footerStart && !isSectionStart( lines[ sectionEnd ] ) ) {
			sectionEnd++;
		}

		var unreleased = copyLines( lines, unreleasedIndex + 1, sectionEnd - 1 );
		var removed    = {};
		for ( var item in noteItems( unreleased ) ) {
			if ( arrayFind( arguments.notes, item.text ) ) {
				for ( var index = item.start; index <= item.end; index++ ) {
					removed[ index ] = true;
				}
			}
		}
		var kept = [];
		for ( var index = 1; index <= arrayLen( unreleased ); index++ ) {
			if ( !structKeyExists( removed, index ) ) {
				kept.append( unreleased[ index ] );
			}
		}

		// Keep a group heading only when a note follows it before the next group heading.
		var notesOnly = [];
		for ( var index = 1; index <= arrayLen( kept ); index++ ) {
			if ( isGroupHeading( kept[ index ] ) ) {
				var hasNotes = false;
				for ( var later = index + 1; later <= arrayLen( kept ) && !isGroupHeading( kept[ later ] ); later++ ) {
					if ( len( trim( kept[ later ] ) ) ) {
						hasNotes = true;
						break;
					}
				}
				if ( !hasNotes ) {
					continue;
				}
			}
			if ( !len( trim( kept[ index ] ) ) && arrayLen( notesOnly ) && !len( trim( notesOnly[ arrayLen( notesOnly ) ] ) ) ) {
				continue;
			}
			notesOnly.append( kept[ index ] );
		}
		trimBlankEdges( notesOnly );

		var outputLines = copyLines( lines, 1, unreleasedIndex );
		outputLines.append( "" );
		if ( arrayLen( notesOnly ) ) {
			outputLines.append( notesOnly, true );
			outputLines.append( "" );
		}
		outputLines.append( copyLines( lines, sectionEnd, arrayLen( lines ) ), true );
		trimBlankEdges( outputLines );

		var lineEnding = arguments.text.crlf ? ( chr( 13 ) & chr( 10 ) ) : chr( 10 );
		return arrayToList( outputLines, lineEnding ) & ( arguments.text.finalNewline ? lineEnding : "" );
	}

	/** A level-three heading, such as "### Fixed", groups notes inside a section. */
	private boolean function isGroupHeading( required string line ){
		return reFind( "^######(?!##)", arguments.line ) > 0;
	}

	/** Returns the text inside the first brackets of a heading or link line, or an empty string. */
	private string function bracketText( required string line ){
		var match = reFind( "\[([^\]]+)\]", arguments.line, 1, true );
		if ( arrayLen( match.pos ) < 2 || match.pos[ 1 ] == 0 ) {
			return "";
		}
		return trim( mid( arguments.line, match.pos[ 2 ], match.len[ 2 ] ) );
	}

	/** A level-two heading starts a section. Level-three headings are groups inside a section. */
	private boolean function isSectionStart( required string line ){
		return reFind( "^####(?!##)", arguments.line ) > 0;
	}

	private boolean function isLinkReference( required string line ){
		return reFind( "^\[[^\]]+\]:\s*\S", trim( arguments.line ) ) > 0;
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
