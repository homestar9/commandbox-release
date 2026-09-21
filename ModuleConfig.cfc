/**
 * Configures the commandbox-release CommandBox module.
 *
 * This module adds CommandBox commands that start with `release`. Examples are
 * `box release publish`, `box release check`, and `box release bump`. Files in
 * commands/release receive command input. Files in models/ do the release work. The
 * templates/ folder holds files that `release init` can copy into a project.
 *
 * The mapping and model namespace always use the package slug. The names stay the same when
 * the module comes from ForgeBox or when the tests load this working copy.
 */
component {

	this.title          = "commandbox-release";
	this.cfmapping      = "commandbox-release";
	this.modelNamespace = "commandbox-release";
	this.autoMapModels  = true;

	function configure(){
		settings = {};
	}
}
