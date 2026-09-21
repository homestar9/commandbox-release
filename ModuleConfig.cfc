/**
 * Configures the commandbox-release CommandBox module.
 *
 * The module adds commands under the `release` command group, also called a namespace.
 * Examples include `box release publish`, `box release check`, and `box release bump`. The
 * command entry points are in commands/release. Components in models/ perform the work. The
 * templates/ folder contains files that `release init` can copy into a project.
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
