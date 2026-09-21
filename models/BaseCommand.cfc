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
	 * Returns true for an expected release error or a failed command called from this command.
	 * The error already has a message for the user.
	 */
	private boolean function isStop( required any exception ){
		var type = arguments.exception.type ?: "";
		return left( type, 8 ) == "Release." || type == "commandException";
	}
}
