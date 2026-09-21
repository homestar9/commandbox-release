/**
 * Creates temporary projects and runs integration test commands in them.
 *
 * Each process runs in the folder provided by the test. The helper returns the exit code and
 * combined output. It does not use a shell. Each argument is passed as a separate value.
 */
component {

	function init( required string repositoryRoot ){
		variables.repositoryRoot = arguments.repositoryRoot;
		variables.processRunner  = application.wirebox.getInstance( "ProcessRunner@commandbox-release" );
		return this;
	}

	/** Creates and returns an empty temporary project folder. */
	string function createProject(){
		var projectRoot = variables.repositoryRoot & "/.test-work/commandbox-release-integration-" & createUUID();
		directoryCreate( projectRoot, true, true );
		return projectRoot;
	}

	/**
	 * Runs one release command in a temporary project. It starts a new CommandBox that loads the
	 * module from this checkout. See tests/support/Invoke.cfc.
	 *
	 * @projectRoot The project folder where the command will run.
	 * @line        The command line, such as "release bump patch --dryRun".
	 */
	struct function runCommand( required string projectRoot, required string line ){
		// Do not add quotes around the value. Java passes it to Windows as one argument and adds
		// any needed quotes. Literal quotes here would split the command incorrectly.
		return runBox(
			arguments.projectRoot,
			[
				"task", "run",
				"taskFile=" & variables.repositoryRoot & "/tests/support/Invoke.cfc",
				":line=" & arguments.line
			]
		);
	}

	/** Runs CommandBox in a temporary project. */
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
		var processArguments = createObject( "java", "java.util.ArrayList" ).init();
		processArguments.add( javaCast( "string", arguments.executable ) );
		for ( var processArgument in arguments.args ) {
			processArguments.add( javaCast( "string", processArgument ) );
		}

		var processBuilder = createObject( "java", "java.lang.ProcessBuilder" ).init( processArguments );
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
}
