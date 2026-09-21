/**
 * Calculates Semantic Versioning values for the bump command.
 *
 * This component does not read or write files. It receives version strings and returns parsed,
 * compared, or updated values. VersionBumper.cfc handles output and file changes.
 */
component {

	/**
	 * Returns the version change levels accepted by VersionBumper.cfc.
	 */
	string function supportedLevels(){
		return "major,minor,patch,prerelease,premajor,preminor,prepatch,none";
	}

	/**
	 * Splits a semantic version into named parts.
	 *
	 * For example, 1.2.3-beta.4+build7 returns major 1, minor 2, patch 3, prerelease
	 * "beta.4", and build metadata "build7".
	 *
	 * @version The version string to parse.
	 */
	struct function parseVersion( required string version ){
		var remainingVersion = trim( arguments.version );
		var buildMetadata     = "";

		if ( find( "+", remainingVersion ) ) {
			var buildSeparator = find( "+", remainingVersion );
			buildMetadata       = mid( remainingVersion, buildSeparator + 1, len( remainingVersion ) );
			remainingVersion    = left( remainingVersion, buildSeparator - 1 );
		}

		var prerelease = "";
		if ( find( "-", remainingVersion ) ) {
			var prereleaseSeparator = find( "-", remainingVersion );
			prerelease              = mid( remainingVersion, prereleaseSeparator + 1, len( remainingVersion ) );
			remainingVersion         = left( remainingVersion, prereleaseSeparator - 1 );
		}

		var versionParts = listToArray( remainingVersion, "." );
		return {
			"major"      : val( versionParts[ 1 ] ?: "0" ),
			"minor"      : val( versionParts[ 2 ] ?: "0" ),
			"patch"      : val( versionParts[ 3 ] ?: "0" ),
			"prerelease" : prerelease,
			"build"      : buildMetadata
		};
	}

	/**
	 * Calculates a version for one supported change level.
	 *
	 * A normal change finishes a matching prerelease. For example, patch changes
	 * 1.2.3-beta.2 to 1.2.3. The prerelease level changes beta.2 to beta.3.
	 *
	 * @current The current version string.
	 * @level   One of the values returned by supportedLevels().
	 * @preid   The prerelease label. An empty value keeps the current label or uses "beta".
	 */
	string function nextVersion( required string current, required string level, string preid = "" ){
		var parsedVersion = parseVersion( arguments.current );
		var hasPrerelease = len( parsedVersion.prerelease ) > 0;
		var label          = len( arguments.preid ) ? arguments.preid : "beta";

		switch ( arguments.level ) {
			case "major":
				if ( hasPrerelease && parsedVersion.minor == 0 && parsedVersion.patch == 0 ) {
					return "#parsedVersion.major#.0.0";
				}
				return "#parsedVersion.major + 1#.0.0";

			case "minor":
				if ( hasPrerelease && parsedVersion.patch == 0 ) {
					return "#parsedVersion.major#.#parsedVersion.minor#.0";
				}
				return "#parsedVersion.major#.#parsedVersion.minor + 1#.0";

			case "patch":
				if ( hasPrerelease ) {
					return "#parsedVersion.major#.#parsedVersion.minor#.#parsedVersion.patch#";
				}
				return "#parsedVersion.major#.#parsedVersion.minor#.#parsedVersion.patch + 1#";

			case "premajor":
				return "#parsedVersion.major + 1#.0.0-#label#.1";

			case "preminor":
				return "#parsedVersion.major#.#parsedVersion.minor + 1#.0-#label#.1";

			case "prepatch":
				return "#parsedVersion.major#.#parsedVersion.minor#.#parsedVersion.patch + 1#-#label#.1";

			case "prerelease":
				return incrementPrerelease( parsedVersion, arguments.preid );
		}

		return arguments.current;
	}

	/**
	 * Compares two versions by Semantic Versioning order. It returns -1 when the first version
	 * is lower, 1 when it is higher, and 0 when both versions have the same order.
	 *
	 * A final version is higher than a prerelease with the same numbers. For example, 1.2.0 is
	 * higher than 1.2.0-beta.3. Build metadata such as +build7 does not affect the result.
	 *
	 * @first  The first version to compare.
	 * @second The second version to compare.
	 */
	numeric function compareVersions( required string first, required string second ){
		var a = parseVersion( arguments.first );
		var b = parseVersion( arguments.second );

		for ( var part in [ "major", "minor", "patch" ] ) {
			if ( a[ part ] != b[ part ] ) {
				return a[ part ] < b[ part ] ? -1 : 1;
			}
		}

		var aIsPrerelease = len( a.prerelease ) > 0;
		var bIsPrerelease = len( b.prerelease ) > 0;
		if ( !aIsPrerelease && !bIsPrerelease ) {
			return 0;
		}
		if ( !aIsPrerelease ) {
			return 1;
		}
		if ( !bIsPrerelease ) {
			return -1;
		}
		return comparePrereleases( a.prerelease, b.prerelease );
	}

	/**
	 * Returns the highest valid version in a list. It ignores invalid versions. It also ignores
	 * prereleases unless includePrerelease is true. It returns an empty string when no value
	 * can be used.
	 *
	 * @versions          Version strings without a tag prefix.
	 * @includePrerelease Allows a prerelease to be returned.
	 */
	string function highestVersion( required array versions, boolean includePrerelease = false ){
		var best = "";
		for ( var candidate in arguments.versions ) {
			var version = trim( candidate );
			if ( !reFind( "^\d+\.\d+\.\d+", version ) ) {
				continue;
			}
			if ( !arguments.includePrerelease && len( parseVersion( version ).prerelease ) ) {
				continue;
			}
			if ( !len( best ) || compareVersions( version, best ) > 0 ) {
				best = version;
			}
		}
		return best;
	}

	/**
	 * Compares prerelease labels one part at a time by SemVer rules. Numeric parts compare as
	 * numbers. A number is lower than a word. A label with fewer equal parts is lower.
	 */
	private numeric function comparePrereleases( required string first, required string second ){
		var aParts = listToArray( arguments.first, "." );
		var bParts = listToArray( arguments.second, "." );
		var count  = max( arrayLen( aParts ), arrayLen( bParts ) );

		for ( var index = 1; index <= count; index++ ) {
			if ( index > arrayLen( aParts ) ) {
				return -1;
			}
			if ( index > arrayLen( bParts ) ) {
				return 1;
			}
			var aPart      = aParts[ index ];
			var bPart      = bParts[ index ];
			var aIsNumeric = reFind( "^\d+$", aPart ) > 0;
			var bIsNumeric = reFind( "^\d+$", bPart ) > 0;

			if ( aIsNumeric && bIsNumeric ) {
				if ( val( aPart ) != val( bPart ) ) {
					return val( aPart ) < val( bPart ) ? -1 : 1;
				}
			} else if ( aIsNumeric != bIsNumeric ) {
				return aIsNumeric ? -1 : 1;
			} else {
				var textOrder = javaCast( "string", aPart ).compareTo( javaCast( "string", bPart ) );
				if ( textOrder != 0 ) {
					return textOrder < 0 ? -1 : 1;
				}
			}
		}
		return 0;
	}

	/**
	 * Adds one to the number at the end of a prerelease label.
	 */
	private string function incrementPrerelease( required struct parsedVersion, string preid = "" ){
		var coreVersion = "#arguments.parsedVersion.major#.#arguments.parsedVersion.minor#.#arguments.parsedVersion.patch#";

		if ( !len( arguments.parsedVersion.prerelease ) ) {
			throw(
				type    = "Release.Version.NotPrerelease",
				message = "#coreVersion# is not a prerelease. Use prepatch, preminor, or premajor to start one."
			);
		}

		var labelParts = listToArray( arguments.parsedVersion.prerelease, "." );
		var label      = arguments.parsedVersion.prerelease;
		var counter    = 0;

		if ( arrayLen( labelParts ) > 1 && isNumeric( labelParts[ arrayLen( labelParts ) ] ) ) {
			counter = val( labelParts[ arrayLen( labelParts ) ] );
			arrayDeleteAt( labelParts, arrayLen( labelParts ) );
			label = arrayToList( labelParts, "." );
		}

		if ( len( arguments.preid ) && arguments.preid != label ) {
			return "#coreVersion#-#arguments.preid#.1";
		}

		return "#coreVersion#-#label#.#counter + 1#";
	}
}
