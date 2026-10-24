/**
 * Provides shared tools for model components.
 *
 * A model component is not a CommandBox command. CommandBox does not automatically give it a
 * print buffer, shell, or command() function. This base component gets those tools from
 * WireBox. It also provides helpers for errors, module file paths, other CommandBox commands,
 * and URL checks.
 *
 * Model components throw a Release exception instead of calling error(). The command that
 * started the model converts that exception into a command error. This design lets tests use
 * model components without running a command.
 */
component {

	property name="shell"          inject="shell";
	property name="print"          inject="PrintBuffer";
	property name="wirebox"        inject="wirebox";
	property name="fileSystemUtil" inject="FileSystem";
	property name="formatterUtil"  inject="Formatter";
	property name="processRunner"  inject="ProcessRunner@commandbox-release";

	/**
	 * Gives the component a loaded project and its settings.
	 *
	 * @config The loaded ProjectConfig.
	 */
	function forProject( required any config ){
		variables.config   = arguments.config;
		variables.settings = arguments.config.getSettings();
		variables.root     = arguments.config.getRoot();
		return this;
	}

	/**
	 * Uses the caller's print buffer. Shared use keeps output from several components in order.
	 * It also makes sure the command prints all buffered text before it ends.
	 *
	 * @printer The CommandBox print buffer to use.
	 */
	function usePrinter( required any printer ){
		variables.print = arguments.printer;
		return this;
	}

	/**
	 * Creates another model component for the same project and print buffer.
	 *
	 * @name The component name, such as "PackageBuilder".
	 */
	function service( required string name ){
		var instance = variables.wirebox.getInstance( arguments.name & "@commandbox-release" ).usePrinter( variables.print );
		if ( structKeyExists( variables, "config" ) ) {
			instance.forProject( variables.config );
		}
		return instance;
	}

	/**
	 * Returns the project's Git repository. Run Git only through it. See RepositoryService.
	 */
	private any function repository(){
		if ( !structKeyExists( variables, "repositoryService" ) ) {
			variables.repositoryService = service( "RepositoryService" );
		}
		return variables.repositoryService;
	}

	/**
	 * Returns the provider for the host of the release remote. GitHub is the only host today.
	 * Run gh only through it. See GitHubProvider.
	 */
	private any function host(){
		if ( !structKeyExists( variables, "hostProvider" ) ) {
			variables.hostProvider = service( "GitHubProvider" );
		}
		return variables.hostProvider;
	}

	/**
	 * Returns recommended patterns missing from the box.json ignore list. These patterns keep
	 * files out of the package. Run `box release init` to add the missing patterns.
	 * Returns an empty array if box.json cannot be read.
	 */
	private array function missingPackageIgnores(){
		var packageData = {};
		try {
			packageData = variables.config.boxJSON();
		} catch ( any ignoredException ) {
			return [];
		}
		var projectSettings = variables.wirebox.getInstance( "ProjectSettingsService@commandbox-release" );
		var isModule        = projectSettings.isModule( packageData, fileExists( variables.root & "/ModuleConfig.cfc" ) );
		return projectSettings.mergeIgnores( packageData.ignore ?: [], projectSettings.recommendedIgnores( isModule ) ).added;
	}

	/**
	 * Creates a CommandBox command runner, such as command( "publish" ).run().
	 *
	 * @name The command name, such as "testbox run".
	 */
	function command( required string name ){
		return variables.wirebox.getInstance( name = "CommandDSL", initArguments = { name : arguments.name } );
	}

	/**
	 * Runs a CommandBox command in a new `box` process from the project root and returns its exit
	 * code. The command's output shows while it runs. testCommand and hooks run this way.
	 *
	 * A new process keeps the command's changes out of the release. A test runner for a
	 * CommandBox module, for example, can unload modules and replace shared mappings. It runs the
	 * box program found on PATH. The process gets no input, so a question it asks reads the end
	 * of the input.
	 *
	 * @commandLine The CommandBox command without "box", such as "run-script test".
	 */
	numeric function runBoxCommand( required string commandLine ){
		var printer = variables.print;
		// Pass the whole command as one argument. box splits it into words the same way its
		// shell does.
		var result = variables.processRunner.run(
			name             = "box",
			args             = [ arguments.commandLine ],
			workingDirectory = variables.root,
			onLine           = function( line ){
				printer.line( arguments.line ).toConsole();
			}
		);
		return result.exitCode;
	}

	/**
	 * Returns a full path inside the installed module.
	 *
	 * @relative A module-relative path, such as "templates/RELEASE.md".
	 */
	string function modulePath( string relative = "" ){
		return expandPath( "/commandbox-release/" & arguments.relative );
	}

	/** Returns the installed module version from its box.json. Returns an empty string on failure. */
	string function moduleVersion(){
		try {
			return trim( deserializeJSON( fileRead( modulePath( "box.json" ) ) ).version ?: "" );
		} catch ( any ignoredException ) {
			return "";
		}
	}

	/**
	 * Stops the model with a one-line message. The calling command reports the error.
	 *
	 * @message A description of the problem.
	 * @type    The exception type. Types that start with Release. are shown without a stack trace.
	 */
	function stop( required string message, string type = "Release.Stop" ){
		throw( type = arguments.type, message = arguments.message );
	}

	/**
	 * Prints detailed instructions and then stops the model with a one-line error.
	 *
	 * CommandBox error() removes line breaks from a message. This function prints the detailed
	 * instructions first so they keep their line breaks. It uses only the short summary for the
	 * final command error.
	 *
	 * @summary A one-line description of the problem.
	 * @detail  The instruction lines to print before the error.
	 * @heading A short heading for the instructions.
	 */
	function fail( required string summary, array detail = [], string heading = "What to do" ){
		if ( arrayLen( arguments.detail ) ) {
			variables.print.line().boldLine( arguments.heading & ":" ).toConsole();
			for ( var line in arguments.detail ) {
				variables.print.yellowLine( "  " & line ).toConsole();
			}
			variables.print.line().toConsole();
		}
		return stop( arguments.summary );
	}

	/**
	 * Converts a struct to readable JSON. It uses the CommandBox formatter when available so
	 * the result matches files written by CommandBox.
	 *
	 * @data The struct to convert.
	 */
	string function formatJSON( required struct data ){
		var json = serializeJSON( arguments.data );
		try {
			return variables.formatterUtil.formatJSON( json );
		} catch ( any ignoredException ) {
			return json;
		}
	}

	/**
	 * Requests a URL without following redirects and returns the HTTP status code. It returns
	 * 0 when the request fails. Callers can then tell a missing server from an HTTP error.
	 *
	 * @url     The URL to request.
	 * @timeout The maximum number of seconds to wait.
	 */
	numeric function probe( required string url, numeric timeout = 15 ){
		var httpResult = "";
		try {
			cfhttp(
				url          = arguments.url,
				method       = "GET",
				timeout      = arguments.timeout,
				throwonerror = false,
				redirect     = false,
				result       = "local.httpResult"
			);
		} catch ( any ignoredException ) {
			return 0;
		}
		return val( httpResult.statuscode ?: "0" );
	}
}
