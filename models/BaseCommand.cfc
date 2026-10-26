/**
 * Provides the shared setup and error handling for each `release` command.
 *
 * It finds the project, loads its settings, and starts the requested model component. It also
 * converts expected model exceptions into command errors.
 *
 * CommandBox keeps command components between runs. The component stores only the injected
 * project locator. Each command run creates a new ProjectConfig.
 */
component {

	property name="locator" inject="ProjectLocator@commandbox-release";

	/**
	 * Finds the project root from the current folder.
	 */
	string function projectRoot(){
		return guard( function(){
			return variables.locator.findRoot( getCWD() );
		} );
	}

	/**
	 * Loads the current project and prints its name, version, and root folder.
	 */
	any function loadProject(){
		return guard( function(){
			var config = getInstance( "ProjectConfig@commandbox-release" ).load( variables.locator.findRoot( getCWD() ) );
			print.line( "Project: #config.slug()# #config.version()# at #config.getRoot()#" ).toConsole();
			return config;
		} );
	}

	/**
	 * Creates a model component that uses this command's print buffer.
	 *
	 * @name   The component name, such as "ReleaseService".
	 * @config The loaded project when the component needs project settings.
	 */
	any function service( required string name, any config ){
		var instance = getInstance( arguments.name & "@commandbox-release" ).usePrinter( print );
		if ( !isNull( arguments.config ) ) {
			instance.forProject( arguments.config );
		}
		return instance;
	}

	/**
	 * Runs a function and reports an expected release error without a stack trace.
	 * It throws unexpected exceptions again so CommandBox can show the full stack trace.
	 *
	 * @work The function to run.
	 */
	any function guard( required any work ){
		try {
			return arguments.work();
		} catch ( any exception ) {
			if ( isStop( exception ) ) {
				return error( exception.message );
			}
			rethrow;
		}
	}

	/**
	 * Decides whether to fix a Gitflow finish that tagged a version without changing box.json.
	 * The model has already printed the manual steps. Returns true when box release can do the
	 * steps and either --fixTag was given or the user answers yes. It never asks in a practice
	 * run or when nobody can answer, such as in CI.
	 *
	 * @config The loaded project.
	 * @args   The command arguments: level, preid, dryRun, and fixTag.
	 */
	boolean function shouldFixTag( required any config, required struct args ){
		var finished = service( "ReleaseService", arguments.config ).finishedWithoutVersion( arguments.args.level, arguments.args.preid );
		if ( !( finished.canFix ?: false ) ) {
			return false;
		}
		if ( arguments.args.fixTag ) {
			return true;
		}
		if ( arguments.args.dryRun || !isInteractive() ) {
			return false;
		}
		return askYesNo( "Do these steps now and publish #finished.version#?", false );
	}

	/** Asks a yes or no question and returns the answer. */
	private boolean function askYesNo( required string message, required boolean defaultAnswer ){
		var answer = lCase( trim( ask( message = arguments.message & " [y/n] ", defaultResponse = arguments.defaultAnswer ? "y" : "n" ) ) );
		if ( !len( answer ) ) {
			return arguments.defaultAnswer;
		}
		return listFindNoCase( "y,yes,true", answer ) > 0;
	}

	/** Returns true when someone can answer a question in this terminal. */
	private boolean function isInteractive(){
		try {
			return shell.isTerminalInteractive();
		} catch ( any ignoredException ) {
			return false;
		}
	}

	/**
	 * Returns true for an expected release error or a failed command called from this command.
	 * The error already has a message for the user.
	 */
	private boolean function isStop( required any exception ){
		var type = arguments.exception.type ?: "";
		return left( type, 8 ) == "Release." || type == "commandException";
	}
}
