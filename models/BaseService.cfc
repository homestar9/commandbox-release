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
	 * Returns the URLs of the project's test server. Look up CommandBox servers only through it.
	 * See TestServer.
	 */
	private any function testServer(){
		if ( !structKeyExists( variables, "testServerService" ) ) {
			variables.testServerService = service( "TestServer" );
		}
		return variables.testServerService;
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
	 * Returns the box.json install scripts that empty the ignore list. See
	 * ProjectSettingsService.ignoreClearingScripts(). Returns an empty array if box.json cannot
	 * be read.
	 */
	private array function ignoreClearingScripts(){
		var packageData = {};
		try {
			packageData = variables.config.boxJSON();
		} catch ( any ignoredException ) {
			return [];
		}
		return variables.wirebox.getInstance( "ProjectSettingsService@commandbox-release" ).ignoreClearingScripts( packageData );
	}

	/**
	 * Returns what an install script that empties the ignore list does.
	 *
	 * @script A result from ignoreClearingScripts().
	 */
	private string function ignoreClearingProblem( required struct script ){
		return "The box.json #arguments.script.name# script runs ""package set ignore"". "
			& "It empties the ignore list each time box install runs it.";
	}

	/**
	 * Returns how to fix an install script that empties the ignore list. release init can remove
	 * only the ColdBox template's script. Other scripts must be changed by hand.
	 *
	 * @script A result from ignoreClearingScripts().
	 */
	private string function ignoreClearingFix( required struct script ){
		return arguments.script.template
			? "To remove the script, run: box release init"
			: "Remove ""package set ignore"" from the #arguments.script.name# script in box.json.";
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
	 * Returns the bump command that changes a released version. A prerelease moves to its next
	 * label, such as beta.3 to beta.4. bump patch would finish it instead.
	 *
	 * @version The version that was already released.
	 */
	private string function bumpAdvice( required string version ){
		var versionService = variables.wirebox.getInstance( "VersionService@commandbox-release" );
		return "box release bump " & ( versionService.isPrerelease( arguments.version ) ? "prerelease" : "patch" );
	}

	/**
	 * Shows a version change that is easy to make by mistake, before anything changes.
	 *
	 * Finishing a prerelease asks first, because patch, minor, and major all finish one. For
	 * example, patch changes 1.0.0-beta.15 to 1.0.0. A practice run and finishPrerelease skip the
	 * question. Without a confirm function, nobody can answer, so this stops. A new major
	 * version only gets a note, because the user asked for it by name.
	 *
	 * @current          The version before the change.
	 * @target           The version after the change.
	 * @advice           The command that makes the next prerelease instead.
	 * @dryRun           Shows the note without asking.
	 * @finishPrerelease Allows the change without asking.
	 * @confirm          A function that asks a yes or no question and returns the answer. An
	 *                   empty string means nobody can answer, such as in CI.
	 * @ask              False shows the note without asking. bump uses this, because it publishes
	 *                   nothing.
	 */
	private void function reviewVersionChange(
		required string current,
		required string target,
		required string advice,
		boolean dryRun           = false,
		boolean finishPrerelease = false,
		any confirm              = "",
		boolean ask              = true
	){
		var versionService = variables.wirebox.getInstance( "VersionService@commandbox-release" );
		if ( !versionService.finishesPrerelease( arguments.current, arguments.target ) ) {
			majorVersionNote( versionService, arguments.current, arguments.target );
			return;
		}

		var from    = versionService.parseVersion( arguments.current );
		var to      = versionService.parseVersion( arguments.target );
		var line    = "#from.major#.#from.minor#.#from.patch#";
		var skipped = line != "#to.major#.#to.minor#.#to.patch#" ? " without publishing #line#" : "";
		variables.print
			.yellowLine( "  note  #arguments.current# -> #arguments.target# finishes the prerelease#skipped#. #arguments.target# is a stable version." )
			.yellowLine( "        To publish the next prerelease instead, run: #arguments.advice#" )
			.toConsole();

		if ( !arguments.ask ) {
			variables.print.yellowLine( "        Nothing is published yet. Check the version before you commit it." ).toConsole();
			return;
		}
		if ( arguments.finishPrerelease ) {
			variables.print.yellowLine( "        --finishPrerelease was given, so the release continues." ).toConsole();
			return;
		}
		if ( arguments.dryRun ) {
			variables.print.yellowLine( "        A real run asks before it continues. Add --finishPrerelease to skip the question." ).toConsole();
			return;
		}
		if ( !isClosure( arguments.confirm ) && !isCustomFunction( arguments.confirm ) ) {
			return stop( "Nothing was changed. Nobody can answer the question here. To publish #arguments.target#, add --finishPrerelease, such as in CI." );
		}
		if ( !arguments.confirm( "Finish the prerelease and publish stable version #arguments.target#?" ) ) {
			return stop( "Nothing was changed. #arguments.target# was not published." );
		}
	}

	/** Prints a note when a stable version starts a new major version, such as 1.4.2 to 2.0.0. */
	private void function majorVersionNote( required any versionService, required string current, required string target ){
		if ( !reFind( "^\d+\.\d+\.\d+", trim( arguments.current ) ) || arguments.versionService.isPrerelease( arguments.target ) ) {
			return;
		}
		var from = arguments.versionService.parseVersion( arguments.current );
		var to   = arguments.versionService.parseVersion( arguments.target );
		if ( to.major <= from.major ) {
			return;
		}
		variables.print
			.yellowLine(
				from.major == 0
					? "  note  #arguments.target# is the first stable version."
					: "  note  #arguments.target# is a new major version. Major versions are for breaking changes."
			)
			.toConsole();
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
	 * @type    The exception type. A command can catch a specific type and offer a fix.
	 */
	function fail(
		required string summary,
		array detail   = [],
		string heading = "What to do",
		string type    = "Release.Stop"
	){
		if ( arrayLen( arguments.detail ) ) {
			variables.print.line().boldLine( arguments.heading & ":" ).toConsole();
			for ( var line in arguments.detail ) {
				variables.print.yellowLine( "  " & line ).toConsole();
			}
			variables.print.line().toConsole();
		}
		return stop( arguments.summary, arguments.type );
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
