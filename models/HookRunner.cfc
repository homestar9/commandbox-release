/**
 * Runs the hooks in release.json. A hook is a CommandBox command that a release runs at a set
 * step. Each hook is off until release.json sets it.
 *
 * `beforePublish` runs after the tests and the build pass and before the release publishes or
 * pushes anything. A failed hook stops the release. For example, a web app can send its
 * production settings to the web server before the push starts a deploy:
 *
 * { "hooks": { "beforePublish": "deploybot env push --yes" } }
 *
 * A hook runs in a new `box` process from the project root, like testCommand. It gets no input,
 * so it must not ask questions. If a later step fails, the next release runs the hook again, so
 * a hook must be safe to run twice.
 */
component extends="commandbox-release.models.BaseService" {

	/**
	 * Returns the command for one hook, or an empty string when the hook is off.
	 *
	 * @name The hook name, such as "beforePublish".
	 */
	string function commandFor( required string name ){
		return variables.settings.hooks[ arguments.name ] ?: "";
	}

	/**
	 * Runs one hook. Returns true when the hook ran and passed. Returns false when the hook is
	 * off, skipped, or only shown in a practice run. Stops when the hook fails.
	 *
	 * @name   The hook name, such as "beforePublish".
	 * @dryRun Shows the command without running it.
	 * @skip   Skips the hook and prints a note.
	 */
	boolean function run( required string name, boolean dryRun = false, boolean skip = false ){
		var hookCommand = commandFor( arguments.name );
		if ( !len( hookCommand ) ) {
			return false;
		}
		if ( arguments.skip ) {
			print.line().yellowLine( "The #arguments.name# command was skipped (requested with skipHooks): box #hookCommand#" ).toConsole();
			return false;
		}
		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "Practice run. This #arguments.name# command would run next:" )
				.line( "  box #hookCommand#" )
				.toConsole();
			return false;
		}

		print
			.line()
			.boldBlueLine( "=== Running the #arguments.name# command ===" )
			.blueLine( "Running: box #hookCommand#" )
			.toConsole();
		var exitCode = runBoxCommand( hookCommand );
		if ( exitCode == 0 ) {
			print.greenLine( "The #arguments.name# command finished." ).toConsole();
			return true;
		}
		if ( !variables.processRunner.commandExists( "box" ) ) {
			return stop(
				"The #arguments.name# command did not start because box was not found. Nothing was published. "
				& "Add the CommandBox folder to PATH and open a new terminal, or use --skipHooks."
			);
		}
		return stop(
			"The #arguments.name# command failed: box #hookCommand# (exit code #exitCode#). Nothing was published. "
			& "Fix the problem, or use --skipHooks to release without it."
		);
	}
}
