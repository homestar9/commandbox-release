/**
 * Finds the project for a release command.
 *
 * A command can run from the project root or one of its child folders. The nearest parent
 * folder with box.json is the project root. The search stops when it finds .git without
 * box.json. This rule prevents a command in an unrelated repository from using a project
 * above that repository.
 */
component singleton {

	/**
	 * Returns the project root with forward slashes and no final slash. It throws
	 * Release.NoProject when no project is found.
	 *
	 * @startDir The first folder to check. This is usually the current folder.
	 */
	string function findRoot( required string startDir ){
		var current = normalise( arguments.startDir );

		while ( len( current ) ) {
			if ( fileExists( current & "/box.json" ) ) {
				return current;
			}
			if ( directoryExists( current & "/.git" ) ) {
				break;
			}
			var parent = reReplace( current, "[\/][^\/]*$", "" );
			if ( parent == current || !find( "/", parent ) ) {
				break;
			}
			current = parent;
		}

		throw(
			type    = "Release.NoProject",
			message = "No box.json file was found in #arguments.startDir# or its parent folders. "
				& "Run this command inside a CommandBox project, or create one with: box release init"
		);
	}

	/**
	 * Returns the release.json path, or an empty string when the project has no settings file.
	 * It throws Release.Config when the project still uses settings from build-template 1.x or
	 * 2.x, because those files are no longer read.
	 *
	 * @root The project root folder.
	 */
	string function configFile( required string root ){
		var base = normalise( arguments.root );
		if ( fileExists( base & "/release.json" ) ) {
			return base & "/release.json";
		}
		for ( var oldFile in [ "build.json", "build/build.json" ] ) {
			if ( fileExists( base & "/" & oldFile ) ) {
				throw(
					type    = "Release.Config",
					message = "This project has #oldFile# from build-template 1.x or 2.x. commandbox-release 3.0 reads release.json instead. "
						& "See the README section ""Upgrading from 1.x or 2.x"", or run: box release init"
				);
			}
		}
		return "";
	}

	/** Changes a path to forward slashes and removes its final slash. */
	private string function normalise( required string path ){
		return reReplace( replace( arguments.path, "\", "/", "all" ), "/+$", "" );
	}
}
