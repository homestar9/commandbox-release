/**
 * Runs programs such as git, gh, and box. It returns their exit code and text output.
 *
 * This component does not throw an exception when a program fails. The caller decides what
 * each exit code means. Some checks, such as `git rev-parse --verify`, use a nonzero exit code
 * as a normal result.
 *
 * Arguments use an array instead of one command string. The program receives each array item
 * as one argument. Paths with spaces do not need extra quotes and cannot split into separate
 * arguments.
 *
 * Java starts the program directly. The command does not use a shell, so pipes, redirects,
 * and wildcards do not work. Each call runs one program with a list of plain arguments.
 */
component singleton {

	function init(){
		variables.binaryCache = {};
		return this;
	}

	/**
	 * Runs one program and returns { exitCode, output }. The output combines standard output
	 * and error output so the caller receives the program's full message.
	 *
	 * The program gets no input. If it asks a question, it reads the end of the input instead
	 * of waiting forever.
	 *
	 * @name             The program name, such as "git".
	 * @args             The argument list, such as [ "status", "--porcelain" ].
	 * @workingDirectory The folder where the program will run. This is usually the project root.
	 * @onLine           Optional. A function that gets each output line as soon as the program
	 *                   prints it. Use it to show the output of a long run while it happens.
	 */
	struct function run(
		required string name,
		array args = [],
		required string workingDirectory,
		any onLine = ""
	){
		var binary  = findBinary( arguments.name );
		var argList = createObject( "java", "java.util.ArrayList" ).init();
		argList.add( javaCast( "string", binary ) );
		for ( var arg in arguments.args ) {
			argList.add( javaCast( "string", arg ) );
		}
		var lineHandler = arguments.onLine;
		var streaming   = !isSimpleValue( lineHandler );

		try {
			var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( argList );
			builder.directory( createObject( "java", "java.io.File" ).init( arguments.workingDirectory ) );
			builder.redirectErrorStream( javaCast( "boolean", true ) );

			var process = builder.start();
			process.getOutputStream().close();
			var reader = createObject( "java", "java.io.BufferedReader" ).init(
				createObject( "java", "java.io.InputStreamReader" ).init( process.getInputStream() )
			);

			var output = createObject( "java", "java.lang.StringBuilder" ).init();
			var line   = reader.readLine();
			while ( !isNull( line ) ) {
				output.append( line ).append( chr( 10 ) );
				if ( streaming ) {
					lineHandler( line );
				}
				line = reader.readLine();
			}
			reader.close();

			return { exitCode : process.waitFor(), output : trim( output.toString() ) };
		} catch ( any exception ) {
			// This error usually means that the program is not installed. Exit code 127 means
			// "command not found," so callers can handle that case directly.
			return {
				exitCode : 127,
				output   : "Could not start '#arguments.name#': #exception.message#"
			};
		}
	}

	/**
	 * Returns true when the program can be found and started.
	 *
	 * @name The program name, such as "gh".
	 */
	boolean function commandExists( required string name ){
		// A found program has a full path. A missing program keeps its original name.
		return findBinary( arguments.name ) != arguments.name;
	}

	/**
	 * Finds a program and returns its full path, such as
	 * C:\Program Files\Git\cmd\git.exe. It returns the original name when no file is found.
	 * The operating system can then try its own lookup and return a clear error.
 *
	 * It searches PATH first. It then searches common installation folders. A terminal keeps
	 * the PATH value from when it started. The second search can find a program that was
	 * installed after the terminal opened.
 *
	 * It stores each result until the CommandBox shell closes.
	 *
	 * @name The program name, for example "git", "gh".
	 */
	string function findBinary( required string name ){
		if ( structKeyExists( variables.binaryCache, arguments.name ) ) {
			return variables.binaryCache[ arguments.name ];
		}

		var jFile     = createObject( "java", "java.io.File" );
		var separator = jFile.separator;
		var resolved  = arguments.name;
		// The empty extension covers Mac and Linux; the rest are the Windows launchers.
		var extensions = [ "", ".exe", ".cmd", ".bat" ];

		var searchDirs = [];
		var pathEnv    = createObject( "java", "java.lang.System" ).getenv( "PATH" );
		if ( !isNull( pathEnv ) ) {
			searchDirs.append( listToArray( pathEnv, jFile.pathSeparator ), true );
		}
		searchDirs.append( wellKnownDirs(), true );

		for ( var searchDirectory in searchDirs ) {
			if ( !len( trim( searchDirectory ) ) ) {
				continue;
			}
			for ( var extension in extensions ) {
				var candidate = reReplace( searchDirectory, "[\\/]$", "" ) & separator & arguments.name & extension;
				if ( fileExists( candidate ) ) {
					resolved = candidate;
					break;
				}
			}
			if ( resolved != arguments.name ) {
				break;
			}
		}

		variables.binaryCache[ arguments.name ] = resolved;
		return resolved;
	}

	/**
	 * The usual install folders to check when PATH does not turn up a program.
	 */
	private array function wellKnownDirs(){
		var system      = createObject( "java", "java.lang.System" );
		var directories = [];

		var programFiles    = system.getenv( "ProgramFiles" );
		var programFilesX86 = system.getenv( "ProgramFiles(x86)" );
		var localAppData    = system.getenv( "LOCALAPPDATA" );

		if ( !isNull( programFiles ) ) {
			directories.append( programFiles & "\GitHub CLI" );
			directories.append( programFiles & "\Git\cmd" );
			directories.append( programFiles & "\Git\bin" );
			directories.append( programFiles & "\nodejs" );
		}
		if ( !isNull( programFilesX86 ) ) {
			directories.append( programFilesX86 & "\GitHub CLI" );
			directories.append( programFilesX86 & "\Git\cmd" );
		}
		if ( !isNull( localAppData ) ) {
			directories.append( localAppData & "\Programs\GitHub CLI" );
			directories.append( localAppData & "\Microsoft\WinGet\Links" );
			directories.append( localAppData & "\Programs\Git\cmd" );
		}

		directories.append( "/usr/local/bin" );
		directories.append( "/usr/bin" );
		directories.append( "/bin" );
		directories.append( "/opt/homebrew/bin" );
		directories.append( "/opt/local/bin" );
		directories.append( "/snap/bin" );

		return directories;
	}
}
