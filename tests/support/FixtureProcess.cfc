/**
 * Creates temporary projects and runs integration test commands in them.
 *
 * Each test bundle calls start() once. That starts one box with this checkout loaded as the
 * module. runCommand() sends each command to that box through its input and reads the output
 * up to the end marker that tests/support/Invoke.cfc prints. Starting box takes about ten
 * seconds and a command takes a few, so one box per bundle keeps the suite short. stop() ends
 * the box.
 *
 * The box runs with CI=true, so commands never ask questions. Only one command runs at a time,
 * because a question would read the next command as its answer.
 *
 * Git and other programs run as their own short processes. Each argument is passed as a
 * separate value. No shell is involved.
 */
component {

	/** How long one command may run. A command that runs tests or a hook starts another box. */
	variables.commandTimeoutSeconds = 600;

	function init( required string repositoryRoot ){
		variables.repositoryRoot = reReplace( replace( arguments.repositoryRoot, "\", "/", "all" ), "/+$", "" );
		variables.processRunner  = application.wirebox.getInstance( "ProcessRunner@commandbox-release" );
		return this;
	}

	/** Creates and returns an empty temporary project folder. */
	string function createProject(){
		var projectRoot = variables.repositoryRoot & "/.test-work/commandbox-release-integration-" & createUUID();
		directoryCreate( projectRoot, true, true );
		return projectRoot;
	}

	/** Starts the shared box and loads this working copy in it. Ends a running box first. */
	function start(){
		stop();
		var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( javaList( [ variables.processRunner.findBinary( "box" ) ] ) );
		builder.directory( createObject( "java", "java.io.File" ).init( variables.repositoryRoot ) );
		builder.redirectErrorStream( javaCast( "boolean", true ) );
		builder.environment().put( "CI", "true" );

		var process = builder.start();
		variables.box = {
			process : process,
			input   : createObject( "java", "java.io.OutputStreamWriter" ).init( process.getOutputStream(), "UTF-8" ),
			output  : process.getInputStream()
		};
		request( line = "", root = "", reload = true );
		return this;
	}

	/** Ends the shared box. Safe to call when none is running. */
	function stop(){
		if ( !structKeyExists( variables, "box" ) ) {
			return this;
		}
		var box = variables.box;
		structDelete( variables, "box" );
		try {
			box.input.write( "exit" & chr( 10 ) );
			box.input.flush();
			box.input.close();
		} catch ( any ignoredException ) {
			// The process may have ended already.
		}
		var seconds = createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS;
		if ( !box.process.waitFor( javaCast( "long", 10 ), seconds ) ) {
			box.process.destroyForcibly();
		}
		return this;
	}

	/**
	 * Runs one release command in a temporary project through the shared box. Starts the box
	 * when it is not running. Returns the exit code and the command's output.
	 *
	 * @projectRoot The project folder where the command will run.
	 * @line        The command line, such as "release bump patch --dryRun".
	 */
	struct function runCommand( required string projectRoot, required string line ){
		if ( !structKeyExists( variables, "box" ) || !variables.box.process.isAlive() ) {
			start();
		}
		return request( line = arguments.line, root = arguments.projectRoot, reload = false );
	}

	/** Runs CommandBox in a temporary project as its own process. */
	struct function runBox( required string projectRoot, required array args ){
		return runProcess(
			workingDirectory = arguments.projectRoot,
			executable       = variables.processRunner.findBinary( "box" ),
			args             = arguments.args
		);
	}

	/** Runs Git in a temporary project. */
	struct function runGit( required string projectRoot, required array args ){
		return runProcess(
			workingDirectory = arguments.projectRoot,
			executable       = variables.processRunner.findBinary( "git" ),
			args             = arguments.args
		);
	}

	/** Runs one program and returns its exit code and combined output. */
	struct function runProcess(
		required string workingDirectory,
		required string executable,
		array args = []
	){
		var processBuilder = createObject( "java", "java.lang.ProcessBuilder" ).init( javaList( [ arguments.executable ].append( arguments.args, true ) ) );
		processBuilder.directory( createObject( "java", "java.io.File" ).init( arguments.workingDirectory ) );
		processBuilder.redirectErrorStream( javaCast( "boolean", true ) );

		var process = processBuilder.start();
		var reader  = createObject( "java", "java.io.BufferedReader" ).init(
			createObject( "java", "java.io.InputStreamReader" ).init( process.getInputStream() )
		);
		var output = createObject( "java", "java.lang.StringBuilder" ).init();
		var line   = reader.readLine();
		while ( !isNull( line ) ) {
			output.append( line ).append( chr( 10 ) );
			line = reader.readLine();
		}
		reader.close();

		return {
			exitCode : process.waitFor(),
			output   : trim( output.toString() )
		};
	}

	/**
	 * Sends one Invoke.cfc request to the shared box and reads its reply. Returns the exit code
	 * and the output between the markers. Stops the box and throws when it ends or does not
	 * answer in time.
	 */
	private struct function request( required string line, required string root, required boolean reload ){
		var box       = variables.box;
		var nonce     = createUUID();
		var begin     = "__INVOKE_BEGIN__ " & nonce;
		var finish    = "__INVOKE_END__ " & nonce;
		var shellLine = 'task run taskFile="#variables.repositoryRoot#/tests/support/Invoke.cfc"'
			& ' :line="#quoted( arguments.line )#"'
			& ' :root="#quoted( replace( arguments.root, "\", "/", "all" ) )#"'
			& ' :nonce=#nonce# :reload=#arguments.reload#';
		box.input.write( shellLine & chr( 10 ) );
		box.input.flush();

		// The end marker counts once its whole line has arrived, including the exit code.
		var bytes    = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
		var deadline = getTickCount() + variables.commandTimeoutSeconds * 1000;
		var text     = "";
		while ( !reFind( finish & " exitCode=\d+[\r\n]", text ) ) {
			var available = box.output.available();
			if ( available > 0 ) {
				bytes.writeBytes( box.output.readNBytes( javaCast( "int", available ) ) );
				text = bytes.toString( "UTF-8" );
			} else if ( !box.process.isAlive() ) {
				structDelete( variables, "box" );
				failRequest( "The shared box ended while running: " & arguments.line, text );
			} else if ( getTickCount() > deadline ) {
				box.process.destroyForcibly();
				structDelete( variables, "box" );
				failRequest( "The shared box did not finish in #variables.commandTimeoutSeconds# seconds: " & arguments.line, text );
			} else {
				sleep( 20 );
			}
		}

		var beginAt   = find( begin, text );
		var finishAt  = find( finish, text );
		var output    = beginAt && beginAt < finishAt ? mid( text, beginAt + len( begin ), finishAt - beginAt - len( begin ) ) : "";
		var tail      = mid( text, finishAt, len( text ) - finishAt + 1 );
		var codeMatch = reFind( "exitCode=(\d+)", tail, 1, true );
		return {
			exitCode : codeMatch.pos[ 1 ] ? val( mid( tail, codeMatch.pos[ 2 ], codeMatch.len[ 2 ] ) ) : 1,
			output   : trim( replace( output, chr( 13 ), "", "all" ) )
		};
	}

	/** Throws with the output received so far, so the test shows what the box printed. */
	private void function failRequest( required string message, required string outputSoFar ){
		throw(
			type    = "Spec.FixtureBox",
			message = arguments.message,
			detail  = trim( replace( arguments.outputSoFar, chr( 13 ), "", "all" ) )
		);
	}

	/** Escapes double quotes for a quoted CommandBox parameter value. */
	private string function quoted( required string value ){
		return replace( arguments.value, '"', '\"', "all" );
	}

	/** Returns a Java list of strings for ProcessBuilder. */
	private any function javaList( required array values ){
		var list = createObject( "java", "java.util.ArrayList" ).init();
		for ( var value in arguments.values ) {
			list.add( javaCast( "string", value ) );
		}
		return list;
	}
}
