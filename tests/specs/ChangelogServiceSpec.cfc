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

			describe( "mergeChangelogs", function(){
				it( "keeps the Unreleased notes on ours and adds the hotfix section", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ fix, first ] } )
					);
				} );

				it( "keeps group headings inside an added section", function(){
					var grouped = { heading : "[1.0.1] - 2026-08-07", notes : h3() & "Fixed" & lf & lf & "- Fix the bug" & lf & lf & h3() & "Changed" & lf & lf & "- Clearer output" };
					var base    = changelog( { sections : [ first ] } );
					var ours    = changelog( { unreleased : h3() & "Added" & lf & lf & "- Develop note", sections : [ first ] } );
					var theirs  = changelog( { sections : [ grouped, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : h3() & "Added" & lf & lf & "- Develop note", sections : [ grouped, first ] } )
					);
				} );

				it( "places a hotfix section below a release section that only ours has", function(){
					var release = { heading : "[1.1.0] - 2026-08-06", notes : "- New feature" };
					var base    = changelog( { sections : [ first ] } );
					var ours    = changelog( { sections : [ release, first ] } );
					var theirs  = changelog( { sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { sections : [ release, fix, first ] } )
					);
				} );

				it( "adds a section at the end when no later section is shared, before the links", function(){
					var older  = { heading : "[0.9.0] - 2025-12-01", notes : "- Old release" };
					var links  = [ "[1.0.0]: https://example.com/v1.0.0" ];
					var base   = changelog( { sections : [ first ], links : links } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ], links : links } );
					var theirs = changelog( { sections : [ first, older ], links : links } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ first, older ], links : links } )
					);
				} );

				it( "keeps the order of two added sections", function(){
					var second = { heading : "[1.0.2] - 2026-08-08", notes : "- Second fix" };
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { sections : [ second, fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ second, fix, first ] } )
					);
				} );

				it( "combines link references the same way as sections", function(){
					var release = { heading : "[1.1.0] - 2026-08-06", notes : "- New feature" };
					var oldLink = "[1.0.0]: https://example.com/v1.0.0";
					var base    = changelog( { sections : [ first ], links : [ oldLink ] } );
					var ours    = changelog( { sections : [ release, first ], links : [ "[1.1.0]: https://example.com/v1.1.0", oldLink ] } );
					var theirs  = changelog( { sections : [ fix, first ], links : [ "[1.0.1]: https://example.com/v1.0.1", oldLink ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( {
							sections : [ release, fix, first ],
							links    : [ "[1.1.0]: https://example.com/v1.1.0", "[1.0.1]: https://example.com/v1.0.1", oldLink ]
						} )
					);
				} );

				it( "takes the text above Unreleased from the branch that changed it", function(){
					var base   = changelog( { header : "## Changelog" & lf & lf & "Old intro.", sections : [ first ] } );
					var ours   = changelog( { header : "## Changelog" & lf & lf & "Old intro.", unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { header : "## Changelog" & lf & lf & "New intro.", sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { header : "## Changelog" & lf & lf & "New intro.", unreleased : "- Develop note", sections : [ fix, first ] } )
					);
				} );

				it( "takes an old section edited on theirs only", function(){
					var fixed  = { heading : first.heading, notes : "- First release, now with the typo fixed" };
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { sections : [ fix, fixed ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ fix, fixed ] } )
					);
				} );

				it( "takes an old section edited on ours only", function(){
					var fixed  = { heading : first.heading, notes : "- First release, reworded" };
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { sections : [ fixed ] } );
					var theirs = changelog( { sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { sections : [ fix, fixed ] } )
					);
				} );

				it( "leaves out a section that one branch removed and the other left alone", function(){
					var older  = { heading : "[0.9.0] - 2025-12-01", notes : "- Old release" };
					var base   = changelog( { sections : [ first, older ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first, older ] } );
					var theirs = changelog( { sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ fix, first ] } )
					);
					// Removed on ours instead.
					expect( changelogService.mergeChangelogs( base, changelog( { sections : [ first ] } ), changelog( { sections : [ fix, first, older ] } ) ) ).toBe(
						changelog( { sections : [ fix, first ] } )
					);
				} );

				it( "keeps one copy of a part that both branches changed in the same way", function(){
					var fixed  = { heading : first.heading, notes : "- First release, reworded" };
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Same note", sections : [ fixed ] } );
					var theirs = changelog( { unreleased : "- Same note", sections : [ fixed ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Same note", sections : [ fixed ] } )
					);
				} );

				it( "combines sections when Unreleased is empty everywhere", function(){
					var release = { heading : "[1.1.0] - 2026-08-06", notes : "- New feature" };
					var base    = changelog( { sections : [ first ] } );
					var ours    = changelog( { sections : [ release, first ] } );
					var theirs  = changelog( { sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { sections : [ release, fix, first ] } )
					);
				} );

				it( "ignores whitespace differences and heading case", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = h2() & "[unreleased]" & lf & lf & lf
						& h2() & " [1.0.1]  -  2026-08-07" & lf & lf & "- Fix the bug   " & lf & lf & lf
						& repeatString( chr( 35 ), 2 ) & "  [1.0.0]  - 2026-01-01" & lf & lf & "-   First release" & lf;

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( {
							unreleased : "- Develop note",
							sections   : [ { heading : " [1.0.1]  -  2026-08-07", notes : "- Fix the bug   " }, first ]
						} )
					);
				} );

				it( "recognises a heading without a space after the hashes", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = h2() & "[Unreleased]" & lf & lf
						& repeatString( chr( 35 ), 2 ) & "[1.0.1] - 2026-08-07" & lf & lf & "- Fix the bug" & lf & lf
						& h2() & first.heading & lf & lf & first.notes & lf;

					var merged = changelogService.mergeChangelogs( base, ours, theirs );
					expect( arrayToList( changelogService.versionHeadings( merged ) ) ).toBe( "1.0.1,1.0.0" );
					expect( merged ).toInclude( "- Develop note" & lf & lf & repeatString( chr( 35 ), 2 ) & "[1.0.1]" );
				} );

				it( "uses the line endings of ours", function(){
					var crlf   = chr( 13 ) & chr( 10 );
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] }, crlf );
					var theirs = changelog( { sections : [ fix, first ] } );

					var merged = changelogService.mergeChangelogs( base, ours, theirs );
					expect( merged ).toBe( changelog( { unreleased : "- Develop note", sections : [ fix, first ] }, crlf ) );
					expect( replace( merged, crlf, "", "all" ) ).notToInclude( chr( 10 ) );

					// Ours with Unix line endings and theirs with Windows line endings.
					var reversed = changelogService.mergeChangelogs( base, changelog( { unreleased : "- Develop note", sections : [ first ] } ), changelog( { sections : [ fix, first ] }, crlf ) );
					expect( reversed ).toBe( changelog( { unreleased : "- Develop note", sections : [ fix, first ] } ) );
					expect( reversed ).notToInclude( chr( 13 ) );
				} );

				it( "keeps a missing final newline on ours", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] }, lf, false );
					var theirs = changelog( { sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ fix, first ] }, lf, false )
					);
				} );

				it( "keeps a reference link inside a section with that section", function(){
					var linked = { heading : first.heading, notes : "- See [the docs][docs]." & lf & lf & "[docs]: https://example.com/docs" & lf & lf & "- First release" };
					var base   = changelog( { sections : [ linked ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ linked ] } );
					var theirs = changelog( { sections : [ fix, linked ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ fix, linked ] } )
					);
				} );

				it( "keeps the comment block from the changelog template above Unreleased", function(){
					var header = "## Changelog" & lf & lf & "<!--" & lf & "How to use this file." & lf & lf & "Keep this comment above [Unreleased]." & lf & "-->";
					var base   = changelog( { header : header, sections : [ first ] } );
					var ours   = changelog( { header : header, unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { header : header, sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( base, ours, theirs ) ).toBe(
						changelog( { header : header, unreleased : "- Develop note", sections : [ fix, first ] } )
					);
				} );

				it( "works without a base when both branches agree on the shared parts", function(){
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { unreleased : "- Develop note", sections : [ fix, first ] } );

					expect( changelogService.mergeChangelogs( "", ours, theirs ) ).toBe(
						changelog( { unreleased : "- Develop note", sections : [ fix, first ] } )
					);
					expect( function(){
						changelogService.mergeChangelogs( "", ours, changelog( { sections : [ fix, first ] } ) );
					} ).toThrow( type = "Release.Changelog.MergeConflict" );
				} );

				it( "stops when a release branch moved notes that develop still has", function(){
					// The release branch started from develop with note A. Develop then added note B.
					var base    = changelog( { unreleased : "- Note A", sections : [ first ] } );
					var ours    = changelog( { unreleased : "- Note A" & lf & "- Note B", sections : [ first ] } );
					var release = { heading : "[1.1.0] - 2026-08-06", notes : "- Note A" };
					var theirs  = changelog( { sections : [ release, first ] } );

					expectConflict( base, ours, theirs, "The [Unreleased] notes in CHANGELOG.md changed on both branches." );
				} );

				it( "stops when both branches added different Unreleased notes", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var theirs = changelog( { unreleased : "- Hotfix leftover", sections : [ fix, first ] } );

					expectConflict( base, ours, theirs, "[Unreleased] notes" );
				} );

				it( "stops when both branches edited the same old section", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { sections : [ { heading : first.heading, notes : "- Edited on develop" } ] } );
					var theirs = changelog( { sections : [ fix, { heading : first.heading, notes : "- Edited on the hotfix" } ] } );

					expectConflict( base, ours, theirs, "The [1.0.0] section in CHANGELOG.md changed on both branches." );
				} );

				it( "stops when one branch removed a section that the other changed", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { unreleased : "- Develop note" } );
					var theirs = changelog( { sections : [ fix, { heading : first.heading, notes : "- Edited on the hotfix" } ] } );

					expectConflict( base, ours, theirs, "The [1.0.0] section in CHANGELOG.md was removed on one branch and changed on the other." );
				} );

				it( "stops when both branches changed the text above Unreleased", function(){
					var base   = changelog( { header : "Intro.", sections : [ first ] } );
					var ours   = changelog( { header : "Develop intro.", sections : [ first ] } );
					var theirs = changelog( { header : "Hotfix intro.", sections : [ fix, first ] } );

					expectConflict( base, ours, theirs, "The text above [Unreleased] in CHANGELOG.md changed on both branches." );
				} );

				it( "stops when a link label points to different URLs", function(){
					var base   = changelog( { sections : [ first ], links : [ "[1.0.0]: https://example.com/v1.0.0" ] } );
					var ours   = changelog( { sections : [ first ], links : [ "[1.0.0]: https://example.com/develop" ] } );
					var theirs = changelog( { sections : [ fix, first ], links : [ "[1.0.0]: https://example.com/hotfix" ] } );

					expectConflict( base, ours, theirs, "The [1.0.0] link in CHANGELOG.md changed on both branches." );
				} );

				it( "stops when a branch has no Unreleased section", function(){
					var base     = changelog( { sections : [ first ] } );
					var complete = changelog( { sections : [ fix, first ] } );
					var missing  = h2() & first.heading & lf & lf & first.notes & lf;

					expectConflict( base, missing, complete, "does not have a ""#h2()#[Unreleased]"" section" );
					expectConflict( base, complete, missing, "does not have a ""#h2()#[Unreleased]"" section" );
				} );

				it( "stops when a version appears twice on one branch", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { sections : [ first ] } );
					var theirs = changelog( { sections : [ fix, first, { heading : "[1.0.1] - 2026-08-08", notes : "- Again" } ] } );

					expectConflict( base, ours, theirs, "The [1.0.1] section appears twice" );
				} );

				it( "stops when both branches added the same version with different notes", function(){
					var base   = changelog( { sections : [ first ] } );
					var ours   = changelog( { sections : [ { heading : "[1.0.1] - 2026-08-07", notes : "- Released on develop" }, first ] } );
					var theirs = changelog( { sections : [ fix, first ] } );

					expectConflict( base, ours, theirs, "The [1.0.1] section in CHANGELOG.md changed on both branches." );
				} );
			} );

			describe( "repeatedNotes", function(){
				it( "finds notes that are under Unreleased and in a listed version", function(){
					var content = changelog( {
						unreleased : h3() & "Fixed" & lf & lf & "  * Fix the bug" & lf & "- Only in Unreleased",
						sections   : [ fix, { heading : "[1.0.0] - 2026-01-01", notes : "- Only in Unreleased" } ]
					} );

					expect( changelogService.repeatedNotes( content, [ "1.0.1" ] ) ).toBe( [ "Fix the bug" ] );
					expect( changelogService.repeatedNotes( content, [ "1.0.1", "1.0.0" ] ) ).toBe( [ "Fix the bug", "Only in Unreleased" ] );
				} );

				it( "returns an empty array when nothing repeats", function(){
					var content = changelog( { unreleased : h3() & "Fixed" & lf & lf & "- Develop note", sections : [ fix, first ] } );
					expect( changelogService.repeatedNotes( content, [ "1.0.1" ] ) ).toBeEmpty();
					expect( changelogService.repeatedNotes( changelog( { sections : [ fix ] } ), [ "1.0.1" ] ) ).toBeEmpty();
				} );
			} );

			describe( "withoutReleasedNotes", function(){
				it( "removes notes that the branch released, so develop's own notes stay unreleased", function(){
					// The release branch started from develop with note A. Develop then added note B.
					var base     = changelog( { unreleased : "- Note A", sections : [ first ] } );
					var ours     = changelog( { unreleased : "- Note B" & lf & "- Note A", sections : [ first ] } );
					var release  = { heading : "[1.1.0] - 2026-08-06", notes : "- Note A" };
					var theirs   = changelog( { sections : [ release, first ] } );
					var prepared = changelogService.withoutReleasedNotes( base, ours, theirs );

					expect( prepared.notes ).toBe( [ "Note A" ] );
					expect( prepared.base ).toBe( changelog( { sections : [ first ] } ) );
					expect( prepared.ours ).toBe( changelog( { unreleased : "- Note B", sections : [ first ] } ) );
					expect( changelogService.mergeChangelogs( prepared.base, prepared.ours, theirs ) ).toBe(
						changelog( { unreleased : "- Note B", sections : [ release, first ] } )
					);
				} );

				it( "removes a note that spans lines and a group heading left without notes", function(){
					var note     = "- Fix the bug" & lf & "  in two lines";
					var base     = changelog( { unreleased : h3() & "Fixed" & lf & lf & note, sections : [ first ] } );
					var ours     = changelog( { unreleased : h3() & "Added" & lf & lf & "- Develop note" & lf & lf & h3() & "Fixed" & lf & lf & note, sections : [ first ] } );
					var hotfix   = { heading : "[1.0.1] - 2026-08-07", notes : h3() & "Fixed" & lf & lf & note };
					var prepared = changelogService.withoutReleasedNotes( base, ours, changelog( { sections : [ hotfix, first ] } ) );

					expect( prepared.notes ).toBe( [ "Fix the bug in two lines" ] );
					expect( prepared.ours ).toBe( changelog( { unreleased : h3() & "Added" & lf & lf & "- Develop note", sections : [ first ] } ) );
				} );

				it( "keeps a note that develop reworded", function(){
					var base     = changelog( { unreleased : "- Note A", sections : [ first ] } );
					var ours     = changelog( { unreleased : "- Note A, reworded" & lf & "- Note B", sections : [ first ] } );
					var release  = { heading : "[1.1.0] - 2026-08-06", notes : "- Note A" };
					var theirs   = changelog( { sections : [ release, first ] } );
					var prepared = changelogService.withoutReleasedNotes( base, ours, theirs );

					expect( prepared.ours ).toBe( ours );
					expect( changelogService.mergeChangelogs( prepared.base, prepared.ours, theirs ) ).toBe(
						changelog( { unreleased : "- Note A, reworded" & lf & "- Note B", sections : [ release, first ] } )
					);
				} );

				it( "changes nothing when develop did not change [Unreleased] or no released note was pending", function(){
					var base   = changelog( { unreleased : "- Note A", sections : [ first ] } );
					var theirs = changelog( { sections : [ { heading : "[1.1.0] - 2026-08-06", notes : "- Note A" }, first ] } );
					var same   = changelogService.withoutReleasedNotes( base, base, theirs );
					expect( same.notes ).toBeEmpty();
					expect( same.ours ).toBe( base );

					var empty   = changelog( { sections : [ first ] } );
					var develop = changelog( { unreleased : "- Develop note", sections : [ first ] } );
					var none    = changelogService.withoutReleasedNotes( empty, develop, changelog( { sections : [ fix, first ] } ) );
					expect( none.notes ).toBeEmpty();
					expect( none.base ).toBe( empty );
					expect( none.ours ).toBe( develop );
				} );

				it( "keeps Windows line endings", function(){
					var crlf     = chr( 13 ) & chr( 10 );
					var base     = changelog( { unreleased : "- Note A", sections : [ first ] } );
					var ours     = changelog( { unreleased : "- Note B" & lf & "- Note A", sections : [ first ] }, crlf );
					var theirs   = changelog( { sections : [ { heading : "[1.1.0] - 2026-08-06", notes : "- Note A" }, first ] } );
					var prepared = changelogService.withoutReleasedNotes( base, ours, theirs );

					expect( prepared.ours ).toBe( changelog( { unreleased : "- Note B", sections : [ first ] }, crlf ) );
				} );
			} );
		} );
	}

	// FIXTURE HELPERS

	variables.lf    = chr( 10 );
	variables.first = { heading : "[1.0.0] - 2026-01-01", notes : "- First release" };
	variables.fix   = { heading : "[1.0.1] - 2026-08-07", notes : "- Fix the bug" };

	private string function h2(){
		return repeatString( chr( 35 ), 2 ) & " ";
	}

	private string function h3(){
		return repeatString( chr( 35 ), 3 ) & " ";
	}

	/**
	 * Builds a changelog in the layout that mergeChangelogs writes: each part separated by one
	 * blank line. Parts: header, unreleased, sections [ { heading, notes } ], links.
	 */
	private string function changelog( struct parts = {}, string lineEnding = chr( 10 ), boolean finalNewline = true ){
		var blocks = [];
		if ( len( arguments.parts.header ?: "" ) ) {
			blocks.append( arguments.parts.header );
		}
		blocks.append( h2() & "[Unreleased]" );
		if ( len( arguments.parts.unreleased ?: "" ) ) {
			blocks.append( arguments.parts.unreleased );
		}
		for ( var section in arguments.parts.sections ?: [] ) {
			blocks.append( h2() & section.heading & lf & lf & section.notes );
		}
		if ( arrayLen( arguments.parts.links ?: [] ) ) {
			blocks.append( arrayToList( arguments.parts.links, lf ) );
		}
		var text = arrayToList( blocks, lf & lf ) & ( arguments.finalNewline ? lf : "" );
		return replace( text, lf, arguments.lineEnding, "all" );
	}

	private void function expectConflict( required string base, required string ours, required string theirs, required string messagePart ){
		var message = "";
		try {
			changelogService.mergeChangelogs( arguments.base, arguments.ours, arguments.theirs );
		} catch ( "Release.Changelog.MergeConflict" exception ) {
			message = exception.message;
		}
		expect( message ).notToBe( "", "Expected a Release.Changelog.MergeConflict exception." );
		expect( message ).toInclude( arguments.messagePart );
	}
}
