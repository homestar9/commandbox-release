/**
 * Does the host-specific release work for GitHub. It uses the GitHub CLI (gh).
 *
 * It checks the gh sign-in, finds OWNER/REPO from the release remote, and creates the GitHub
 * Release. It also gives SSH key advice for github.com. Git itself runs through
 * RepositoryService, which works the same way for every host.
 */
component extends="commandbox-release.models.BaseService" {

	property name="processRunner" inject="ProcessRunner@commandbox-release";

	/**
	 * Checks the GitHub CLI sign-in. Returns { state, output }. The state is "ready", "missing"
	 * when gh is not installed, or "signedOut".
	 */
	struct function signInState(){
		var result = gh( [ "auth", "status" ] );
		var state  = result.exitCode == 0 ? "ready" : ( result.exitCode == 127 ? "missing" : "signedOut" );
		return { "state" : state, "output" : result.output };
	}

	/**
	 * Returns OWNER/REPO for a github.com remote URL. It returns an empty string for any other
	 * URL. It reads HTTPS, SSH, and scp-style URLs, such as git@github.com:owner/repo.git.
	 *
	 * @remoteUrl The URL from git remote get-url.
	 */
	string function repoFromUrl( required string remoteUrl ){
		var value = trim( arguments.remoteUrl );
		var match = reFindNoCase(
			"^(?:https?://(?:[^@/]+@)?|ssh://(?:[^@/]+@)?|[^@/:]+@)github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$",
			value,
			1,
			true
		);
		if ( !match.pos[ 1 ] ) {
			return "";
		}
		return mid( value, match.pos[ 2 ], match.len[ 2 ] ) & "/" & mid( value, match.pos[ 3 ], match.len[ 3 ] );
	}

	/** Returns OWNER/REPO for the release remote, or an empty string when it is not on github.com. */
	string function repo(){
		return repoFromUrl( repository().remoteUrl() );
	}

	/**
	 * Returns the gh arguments that create a GitHub Release.
	 *
	 * @tagName    The version tag.
	 * @notesFile  A file with the release notes. A file keeps the Markdown unchanged.
	 * @assets     Files to attach, such as the zip and its checksum.
	 * @prerelease Marks the release as a prerelease.
	 */
	array function releaseArgs(
		required string tagName,
		required string notesFile,
		array assets       = [],
		boolean prerelease = false
	){
		var args = [ "release", "create", arguments.tagName, "--title", arguments.tagName, "--notes-file", arguments.notesFile ];
		if ( arguments.prerelease ) {
			args.append( "--prerelease" );
		}
		// gh picks its own repository when the checkout has more than one remote. Use the repository
		// that the tag is pushed to.
		var gitHubRepo = repo();
		if ( len( gitHubRepo ) ) {
			args.append( [ "--repo", gitHubRepo ], true );
		}
		return args.append( arguments.assets, true );
	}

	/**
	 * Creates the GitHub Release. Throws Release.GitHub with gh's output when it fails.
	 *
	 * @args The arguments from releaseArgs().
	 */
	function createRelease( required array args ){
		var result = gh( arguments.args );
		if ( result.exitCode != 0 ) {
			throw( type = "Release.GitHub", message = "The GitHub Release could not be created (#result.output#).", detail = result.output );
		}
		return this;
	}

	/**
	 * Returns advice when Git output shows that the remote rejected the SSH key. Returns an empty
	 * array for other output.
	 *
	 * @remoteName The remote name, such as origin.
	 * @gitOutput  The output from the failed Git command.
	 */
	array function remoteHelp( required string remoteName, required string gitOutput ){
		if ( !( arguments.gitOutput contains "publickey" ) ) {
			return [];
		}
		return [
			"Git cannot sign in to the remote. Add your SSH key at:",
			"https://github.com/settings/ssh/new, or change the remote to HTTPS:",
			"",
			"  git remote set-url #arguments.remoteName# https://github.com/<you>/<repo>.git",
			"  gh auth setup-git"
		];
	}

	private struct function gh( required array args ){
		return variables.processRunner.run( "gh", arguments.args, variables.root );
	}
}
