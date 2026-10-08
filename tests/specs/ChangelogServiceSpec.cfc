/** Checks changelog sections with Unix and Windows line endings. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "ChangelogService", function(){
			beforeEach( function(){
				changelogService = model( "ChangelogService" );
			} );

			it( "moves Unreleased notes into a dated version section", function(){
				var lf    = chr( 10 );
				var h2    = repeatString( chr( 35 ), 2 ) & " ";
				var h3    = repeatString( chr( 35 ), 3 ) & " ";
				var input = h2 & "[Unreleased]" & lf & lf
					& h3 & "Added" & lf & "- Clearer output" & lf & lf
					& h2 & "[1.0.0] - 2026-01-01" & lf & "- First release";
				var output = changelogService.moveUnreleasedNotes( input, "1.1.0", "2026-08-07" );

				expect( output ).toInclude( h2 & "[Unreleased]" & lf & lf & h2 & "[1.1.0] - 2026-08-07" );
				expect( output ).toInclude( h3 & "Added" & lf & "- Clearer output" );
				expect( output ).toInclude( h2 & "[1.0.0] - 2026-01-01" );
			} );

			it( "preserves Windows line endings", function(){
				var crlf  = chr( 13 ) & chr( 10 );
				var h2    = repeatString( chr( 35 ), 2 ) & " ";
				var input = h2 & "[Unreleased]" & crlf & crlf & "- Fixed" & crlf & crlf
					& h2 & "[1.0.0] - 2026-01-01" & crlf & "- First";
				var output = changelogService.moveUnreleasedNotes( input, "1.0.1", "2026-08-07" );

				expect( output ).toInclude( h2 & "[1.0.1] - 2026-08-07" & crlf );
				expect( replace( output, crlf, "", "all" ) ).notToInclude( chr( 10 ) );
			} );

			it( "reports a missing Unreleased section", function(){
				expect( function(){
					changelogService.moveUnreleasedNotes( "#chr( 35 )# Changelog", "1.0.1", "2026-08-07" );
				} ).toThrow( type = "Release.Changelog.MissingUnreleased" );
			} );

			it( "reports an empty Unreleased section", function(){
				var lf = chr( 10 );
				var h2 = repeatString( chr( 35 ), 2 ) & " ";
				expect( function(){
					changelogService.moveUnreleasedNotes(
						h2 & "[Unreleased]" & lf & lf & h2 & "[1.0.0] - 2026-01-01" & lf & "- First",
						"1.0.1",
						"2026-08-07"
					);
				} ).toThrow( type = "Release.Changelog.EmptyUnreleased" );
			} );

			it( "names a group heading written at the version level", function(){
				var lf      = chr( 10 );
				var h2      = repeatString( chr( 35 ), 2 ) & " ";
				var message = "";
				try {
					changelogService.moveUnreleasedNotes(
						h2 & "[Unreleased]" & lf & lf & h2 & "Added" & lf & "- Note",
						"1.0.1",
						"2026-08-07"
					);
				} catch ( "Release.Changelog.EmptyUnreleased" e ) {
					message = e.message;
				}
				expect( message ).toInclude( """" & h2 & "Added""" );
				expect( message ).toInclude( repeatString( chr( 35 ), 3 ) & " Added" );
			} );

			it( "reads one version without matching a longer prerelease version", function(){
				var lf    = chr( 10 );
				var h2    = repeatString( chr( 35 ), 2 ) & " ";
				var input = h2 & "[1.2.0-beta.1] - 2026-08-01" & lf & "Beta notes" & lf & lf
					& h2 & "[1.2.0] - 2026-08-07" & lf & "Final notes";
				expect( changelogService.extractReleaseNotes( input, "1.2.0" ) ).toBe( "Final notes" );
			} );

			it( "lists version headings in file order without Unreleased", function(){
				var crlf  = chr( 13 ) & chr( 10 );
				var h2    = repeatString( chr( 35 ), 2 ) & " ";
				var input = h2 & "[Unreleased]" & crlf & crlf
					& h2 & "[1.4.2] - 2028-08-10" & crlf & "- Latest" & crlf & crlf
					& h2 & "[1.4.1] - 2028-08-07" & crlf & "- Older" & crlf & crlf
					& "[1.4.2]: https://example.com/compare/v1.4.1...v1.4.2";
				expect( arrayToList( changelogService.versionHeadings( input ) ) ).toBe( "1.4.2,1.4.1" );
			} );

			it( "reports missing and empty version sections", function(){
				var lf = chr( 10 );
				var h2 = repeatString( chr( 35 ), 2 ) & " ";
				expect( function(){
					changelogService.extractReleaseNotes( h2 & "[1.0.0]" & lf & "Notes", "2.0.0" );
				} ).toThrow( type = "Release.Changelog.MissingVersion" );

				expect( function(){
					changelogService.extractReleaseNotes(
						h2 & "[1.0.0]" & lf & lf & h2 & "[0.9.0]" & lf & "Old",
						"1.0.0"
					);
				} ).toThrow( type = "Release.Changelog.EmptyVersion" );
			} );
		} );
	}
}
