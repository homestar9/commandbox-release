/**
 * Runs Git for one project. Each instance is bound to the project root and the release remote.
 *
 * Callers ask questions and request changes by name. They do not build Git arguments or read
 * exit codes. Expected states come back as values, such as a missing tag or a remote that
 * cannot be reached. Unexpected failures throw Release.Git with Git's output in the detail.
 * A missing Git program throws Release.Git.Missing.
 *
 * Git works the same way for every host. Host-specific work, such as creating a GitHub
 * Release, belongs in a host provider. See GitHubProvider.
 */
component extends="commandbox-release.models.BaseService" {

	property name="processRunner" inject="ProcessRunner@commandbox-release";

	/**
	 * Binds the project root and the release remote from release.json.
	 *
	 * @config The loaded ProjectConfig.
	 */
	function forProject( required any config ){
		super.forProject( arguments.config );
		variables.remote = variables.settings.remote;
		return this;
	}

	/**
	 * Binds a folder and a remote name without release.json. `release init` and the specs use it.
	 *
	 * @root   The project root folder.
	 * @remote The remote name.
	 */
	function forRoot( required string root, string remote = "origin" ){
		variables.root   = arguments.root;
		variables.remote = arguments.remote;
		return this;
	}

	// REPOSITORY STATE

	/** Returns the name of the release remote, such as origin. */
	string function remoteName(){
		return variables.remote;
	}

	/** Returns the URL of the release remote, or an empty string when Git has no remote with that name. */
	string function remoteUrl(){
		var result = git( [ "remote", "get-url", variables.remote ] );
		return result.exitCode == 0 ? trim( result.output ) : "";
	}

	/**
	 * Returns one line for each uncommitted change, in git status --porcelain format. Returns an
	 * empty array for a clean checkout. Throws when the folder is not a Git repository.
	 */
	array function changedFiles(){
		var status = git( [ "status", "--porcelain" ] );
		if ( status.exitCode != 0 ) {
			gitError( "Git could not read this folder (#status.output#). Check that it is a Git repository.", status );
		}
		return listToArray( status.output, chr( 10 ) );
	}

	/**
	 * Returns the current branch name, or HEAD for a detached checkout. It also works before the
	 * first commit and in linked worktrees.
	 */
	string function currentBranch(){
		var branch = git( [ "symbolic-ref", "--quiet", "--short", "HEAD" ] );
		if ( branch.exitCode == 0 && len( trim( branch.output ) ) ) {
			return trim( branch.output );
		}
		// Exit code 1 means that HEAD is a commit instead of a branch.
		if ( branch.exitCode == 1 ) {
			return "HEAD";
		}
		return gitError( "Git could not identify the current branch (#branch.output#). Check that this is a Git repository.", branch );
	}

	/** Returns the full SHA of the current commit. */
	string function headCommit(){
		var head = git( [ "rev-parse", "HEAD" ] );
		if ( head.exitCode != 0 ) {
			gitError( "Git could not identify the current commit (#head.output#).", head );
		}
		return trim( head.output );
	}

	/** Checks that the release remote answers. Returns { ok, output }. */
	struct function canReachRemote(){
		var result = git( [ "ls-remote", "--exit-code", variables.remote, "HEAD" ] );
		return { "ok" : result.exitCode == 0, "output" : result.output };
	}

	// BRANCHES

	/** Returns true when a local branch exists. */
	boolean function branchExists( required string name ){
		return git( [ "rev-parse", "-q", "--verify", "refs/heads/" & arguments.name ] ).exitCode == 0;
	}

	/** Returns true when the last fetch saw the branch on the release remote. */
	boolean function remoteBranchExists( required string name ){
		return git( [ "rev-parse", "-q", "--verify", "refs/remotes/" & variables.remote & "/" & arguments.name ] ).exitCode == 0;
	}

	/** Returns the local branches whose names start with a prefix. */
	array function branchesWithPrefix( required string prefix ){
		var names = [];
		var refs  = git( [ "for-each-ref", "--format=%(refname:short)", "refs/heads/" ] );
		for ( var name in listToArray( refs.output, chr( 10 ) ) ) {
			if ( startsWith( trim( name ), arguments.prefix ) ) {
				names.append( trim( name ) );
			}
		}
		return names;
	}

	/** Returns true when the first commit is in the history of the second commit. */
	boolean function isAncestor( required string ancestor, required string descendant ){
		return git( [ "merge-base", "--is-ancestor", arguments.ancestor, arguments.descendant ] ).exitCode == 0;
	}

	/** Returns Git's ID for the files of a branch or commit. Matching IDs mean the files are identical. */
	string function treeOf( required string ref ){
		return trim( git( [ "rev-parse", arguments.ref & "^{tree}" ] ).output );
	}

	/**
	 * Returns a file's text from a branch or commit. Returns an empty string when the file or
	 * the ref is missing.
	 *
	 * @ref  A ref, such as refs/heads/master.
	 * @path A path from the project root, such as box.json.
	 */
	string function fileAt( required string ref, required string path ){
		var shown = git( [ "show", arguments.ref & ":./" & arguments.path ] );
		return shown.exitCode == 0 ? shown.output : "";
	}

	/**
	 * Checks whether the branch on the release remote contains the current commit. Returns
	 * "yes", "no", or "unknown" when the remote or the commit cannot be checked.
	 */
	string function remoteBranchHasHead( required string branch ){
		var remoteBranch = git( [ "ls-remote", variables.remote, "refs/heads/" & arguments.branch ] );
		if ( remoteBranch.exitCode != 0 || !len( trim( remoteBranch.output ) ) ) {
			return "unknown";
		}
		var remoteCommit = listFirst( listFirst( remoteBranch.output, chr( 10 ) ), chr( 9 ) );
		var ancestry     = git( [ "merge-base", "--is-ancestor", "HEAD", remoteCommit ] );
		if ( ancestry.exitCode == 0 ) {
			return "yes";
		}
		return ancestry.exitCode == 1 ? "no" : "unknown";
	}

	/**
	 * Returns the Gitflow branch settings from Git config. GitKraken and git flow both store them
	 * there. Missing values use the Gitflow defaults. production is empty when Gitflow does not
	 * set it.
	 */
	struct function gitflowBranches(){
		return {
			"production"    : gitConfig( "gitflow.branch.master", "" ),
			"develop"       : gitConfig( "gitflow.branch.develop", "develop" ),
			"releasePrefix" : gitConfig( "gitflow.prefix.release", "release/" ),
			"hotfixPrefix"  : gitConfig( "gitflow.prefix.hotfix", "hotfix/" )
		};
	}

	// TAGS

	/** Returns "missing", "atHead", or "elsewhere" for a local tag. */
	string function localTag( required string tagName ){
		var tagged = git( [ "rev-parse", "-q", "--verify", "refs/tags/" & arguments.tagName ] );
		if ( tagged.exitCode != 0 ) {
			return "missing";
		}
		var tagCommit = git( [ "rev-list", "-n", "1", "refs/tags/" & arguments.tagName ] );
		return tagCommit.exitCode == 0 && trim( tagCommit.output ) == headCommit() ? "atHead" : "elsewhere";
	}

	/**
	 * Checks one tag on the release remote without downloading it. Returns { status, commit, output }.
	 * The status is "present", "missing", or "unknown". A present tag also includes its commit.
	 *
	 * git ls-remote prints each match as "<sha><tab><ref>". For an annotated tag, the ^{} pattern
	 * adds a second line ending in ^{}. The SHA on that line is the tagged commit. Without that
	 * pattern, Git prints only the tag object's SHA. A lightweight tag already uses the commit SHA.
	 * Exit code 2 means that the remote does not have the tag. Another nonzero code means that the
	 * remote could not be checked.
	 */
	struct function remoteTag( required string tagName ){
		var ref    = "refs/tags/" & arguments.tagName;
		var result = git( [ "ls-remote", "--exit-code", "--tags", variables.remote, ref, ref & "^{}" ] );
		if ( result.exitCode == 2 ) {
			return { "status" : "missing", "commit" : "", "output" : result.output };
		}
		if ( result.exitCode != 0 ) {
			return { "status" : "unknown", "commit" : "", "output" : result.output };
		}

		var commit = "";
		for ( var line in listToArray( result.output, chr( 10 ) ) ) {
			var sha     = trim( listFirst( line, chr( 9 ) ) );
			var lineRef = trim( listLast( line, chr( 9 ) ) );
			if ( lineRef == ref & "^{}" ) {
				commit = sha;
				break;
			}
			if ( lineRef == ref ) {
				commit = sha;
			}
		}
		return { "status" : "present", "commit" : commit, "output" : result.output };
	}

	/**
	 * Decides whether a version tag can be released from the current commit.
	 *
	 * Returns { mode, reason, local, remote, remoteCommit, output }:
	 * - mode "new": no tag exists yet, here or on the remote. The release creates it.
	 * - mode "existing": the local tag points to this commit. The remote has the same tag or none.
	 * - mode "conflict": the tag cannot be used. reason says why:
	 *   localElsewhere  the local tag points to another commit, so that version was released.
	 *   remoteElsewhere the remote tag points to another commit.
	 *   remoteOnly      the remote has the tag at this commit, but this checkout does not.
	 *   remoteUnknown   the remote could not be checked.
	 *
	 * local is "missing", "atHead", or "elsewhere". remote is "present", "missing", "unknown",
	 * or empty when the remote was not checked.
	 */
	struct function tagRelease( required string tagName ){
		var result = {
			"mode"         : "new",
			"reason"       : "",
			"local"        : localTag( arguments.tagName ),
			"remote"       : "",
			"remoteCommit" : "",
			"output"       : ""
		};
		if ( result.local == "elsewhere" ) {
			result.mode   = "conflict";
			result.reason = "localElsewhere";
			return result;
		}

		var onRemote        = remoteTag( arguments.tagName );
		result.remote       = onRemote.status;
		result.remoteCommit = onRemote.commit;
		result.output       = onRemote.output;

		if ( onRemote.status == "unknown" ) {
			result.mode   = "conflict";
			result.reason = "remoteUnknown";
		} else if ( onRemote.status == "present" && onRemote.commit != headCommit() ) {
			result.mode   = "conflict";
			result.reason = "remoteElsewhere";
		} else if ( onRemote.status == "present" && result.local == "missing" ) {
			result.mode   = "conflict";
			result.reason = "remoteOnly";
		} else if ( result.local == "atHead" ) {
			result.mode = "existing";
		}
		return result;
	}

	/** Creates a lightweight tag at the current commit. */
	function createTag( required string tagName ){
		var result = git( [ "tag", arguments.tagName ] );
		if ( result.exitCode != 0 ) {
			gitError( "Tag #arguments.tagName# could not be created: #result.output#", result );
		}
		return this;
	}

	// CHANGES

	/** Gets new commits and tags from the release remote. Local branches do not change. */
	function fetch(){
		var result = git( [ "fetch", variables.remote ] );
		if ( result.exitCode != 0 ) {
			gitError( "git fetch from #variables.remote# failed (#result.output#).", result );
		}
		return this;
	}

	/** Adds the remote branch's commits to the current branch without a merge commit. */
	function pullFastForward( required string branch ){
		var result = git( [ "pull", "--ff-only", variables.remote, arguments.branch ] );
		if ( result.exitCode != 0 ) {
			gitError( "git pull from #variables.remote# failed (#result.output#).", result );
		}
		return this;
	}

	/**
	 * Adds the remote's commits to a local branch when the local branch has no commits of its own.
	 * Uses the last fetched copy of the remote branch. Returns:
	 * - "current" when there is nothing to add, or the remote has no copy of the branch.
	 * - "updated" when the branch now has the remote's commits.
	 * - "diverged" when both have commits that the other does not have. Nothing changes.
	 *
	 * @name    The local branch.
	 * @current The checked-out branch. Git must merge into it instead of moving the ref.
	 */
	string function fastForward( required string name, required string current ){
		var remoteRef = git( [ "rev-parse", "-q", "--verify", "refs/remotes/" & variables.remote & "/" & arguments.name ] );
		if ( remoteRef.exitCode != 0 ) {
			return "current";
		}
		var remoteCommit = trim( remoteRef.output );
		var localCommit  = trim( git( [ "rev-parse", "refs/heads/" & arguments.name ] ).output );
		if ( localCommit == remoteCommit || isAncestor( remoteCommit, localCommit ) ) {
			return "current";
		}
		if ( !isAncestor( localCommit, remoteCommit ) ) {
			return "diverged";
		}

		var updated = arguments.name == arguments.current
			? git( [ "merge", "--ff-only", variables.remote & "/" & arguments.name ] )
			: git( [ "update-ref", "refs/heads/" & arguments.name, remoteCommit, localCommit ] );
		if ( updated.exitCode != 0 ) {
			gitError( "#arguments.name# could not be updated from #variables.remote# (#updated.output#).", updated );
		}
		return "updated";
	}

	/** Creates a branch from another branch and switches to it. */
	function createBranch( required string name, required string from ){
		var created = git( [ "switch", "-c", arguments.name, arguments.from ] );
		if ( created.exitCode != 0 ) {
			gitError( "#arguments.name# could not be created (#created.output#).", created );
		}
		return this;
	}

	/** Switches to a local branch. */
	function switchTo( required string name ){
		var switched = git( [ "switch", arguments.name ] );
		if ( switched.exitCode != 0 ) {
			gitError( "Git could not switch to #arguments.name# (#switched.output#).", switched );
		}
		return this;
	}

	/**
	 * Merges a branch into the current branch with a merge commit. Git does nothing if the
	 * current branch already contains the commits. On failure, cancel the merge and throw.
	 */
	function merge( required string branch ){
		var merged = git( [ "merge", "--no-ff", "--no-edit", arguments.branch ] );
		if ( merged.exitCode != 0 ) {
			git( [ "merge", "--abort" ] );
			gitError( "#arguments.branch# could not be merged (#merged.output#).", merged );
		}
		return this;
	}

	/** Stages only the listed files and commits them. Other changes stay out of the commit. */
	function commitFiles( required array files, required string message ){
		var added = git( [ "add" ].append( arguments.files, true ) );
		if ( added.exitCode != 0 ) {
			gitError( "Git could not stage #arrayToList( arguments.files, ", " )# (#added.output#).", added );
		}
		var committed = git( [ "commit", "-m", arguments.message ] );
		if ( committed.exitCode != 0 ) {
			gitError( "Git could not commit ""#arguments.message#"" (#committed.output#).", committed );
		}
		return this;
	}

	/**
	 * Pushes branches or tags to the release remote.
	 *
	 * @refs Branch or tag names, such as [ "master", "v1.0.0" ].
	 */
	function push( required array refs ){
		var pushed = git( [ "push", variables.remote ].append( arguments.refs, true ) );
		if ( pushed.exitCode != 0 ) {
			gitError( "Git could not push #arrayToList( arguments.refs, " " )# to #variables.remote# (#pushed.output#).", pushed );
		}
		return this;
	}

	/** Deletes a local branch, even when its copy on the remote is behind. */
	function deleteBranch( required string name ){
		var deleted = git( [ "branch", "-D", arguments.name ] );
		if ( deleted.exitCode != 0 ) {
			gitError( "#arguments.name# could not be deleted (#deleted.output#).", deleted );
		}
		return this;
	}

	/**
	 * Deletes a branch on the release remote. Returns false when the remote does not have the
	 * branch or cannot be checked.
	 */
	boolean function deleteRemoteBranch( required string name ){
		var onRemote = git( [ "ls-remote", "--exit-code", "--heads", variables.remote, "refs/heads/" & arguments.name ] );
		if ( onRemote.exitCode != 0 ) {
			return false;
		}
		var deleted = git( [ "push", variables.remote, "--delete", arguments.name ] );
		if ( deleted.exitCode != 0 ) {
			gitError( "#arguments.name# could not be deleted on #variables.remote# (#deleted.output#).", deleted );
		}
		return true;
	}

	// GIT HELPERS

	/**
	 * Runs Git in the project root and returns { exitCode, output }. A nonzero exit code is a
	 * normal result for many questions. Only a missing Git program throws.
	 */
	private struct function git( required array args ){
		var result = variables.processRunner.run( "git", arguments.args, variables.root );
		if ( result.exitCode == 127 ) {
			throw(
				type    = "Release.Git.Missing",
				message = "Git was not found. Install it, or open a new terminal if you installed it recently.",
				detail  = result.output
			);
		}
		return result;
	}

	/** Throws Release.Git with Git's output in the detail. */
	private function gitError( required string message, required struct result ){
		throw( type = "Release.Git", message = arguments.message, detail = arguments.result.output );
	}

	/** Returns a Git config value, or the default when it is missing or empty. */
	private string function gitConfig( required string key, required string defaultValue ){
		var result = git( [ "config", "--get", arguments.key ] );
		return result.exitCode == 0 && len( trim( result.output ) ) ? trim( result.output ) : arguments.defaultValue;
	}

	private boolean function startsWith( required string text, required string prefix ){
		return len( arguments.prefix ) && left( arguments.text, len( arguments.prefix ) ) == arguments.prefix;
	}
}
