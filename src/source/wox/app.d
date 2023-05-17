module wox.app;

import std.stdio;
import std.string;
import std.algorithm;
import std.array;
import std.conv;
import std.process;
static import std.file;
static import std.path;
import std.parallelism : totalCPUs;
import commandr;

import wox.host.builder;
import wox.log;

enum APP_VERSION = "v0.4.0";
enum DEFAULT_BUILDFILE_NAME = "build.wox";

int main(string[] args) {
	// args before -- go to wox, args after -- go to the buildfile
	auto split_args = args.split("--");
	auto wox_args = split_args[0];
	auto buildfile_args = split_args.length > 1 ? split_args[1] : [];

	auto a = new Program("wox", APP_VERSION).summary("A flexible recipe build system inspired by Make")
		.author("redthing1")
		.add(new Argument("targets", "targets to build").repeating.optional)
		.add(new Flag("v", "verbose", "turns on more verbose output").repeating)
		.add(new Flag("q", "quiet", "reduces output verbosity").repeating)
		.add(new Option("f", "file", "build file to use")
				.defaultValue(DEFAULT_BUILDFILE_NAME))
		.add(new Option("C", "workdir", "change to this directory before doing anything")
				.defaultValue("."))
		.add(new Option("z", "graphviz_file", "dump a graphviz of the dependency graph to this file"))
		.add(new Option("j", "jobs", "number of jobs to run in parallel")
				.defaultValue(totalCPUs.to!string))
		.add(new Flag("k", "cache", "enable cache database"))
		.add(new Flag("l", "list_targets", "list targets in build file"))
		.add(new Flag("n", "dry_run", "don't actually run any commands"))
		.parse(wox_args);

	auto verbose_count = min(a.occurencesOf("verbose"), 2);
	auto quiet_count = min(a.occurencesOf("quiet"), 2);
	auto logger_verbosity = (Verbosity.info.to!int + verbose_count - quiet_count).to!Verbosity;

	auto log = Logger(logger_verbosity);
	log.use_colors = true;
	log.meta_timestamp = false;
	log.source = "wox";

	auto env_vars = environment.toAA();

	log.trace("invocation: %s", args);
	log.trace("  build file: %s", a.option("file"));
	log.trace("  targets: %s", a.args("targets"));

	// change to working directory
	auto workdir = a.option("workdir");
	if (!std.file.exists(workdir)) {
		writefln("Error: working directory '%s' does not exist", workdir);
		return 1;
	}

	log.trace("changing to working directory '%s'", workdir);

	std.file.chdir(workdir);

	// open build file
	auto buildfile_path = a.option("file");
	if (!std.file.exists(buildfile_path)) {
		writefln("Error: build file '%s' does not exist", buildfile_path);
		return 1;
	}
	auto buildfile_basename = std.path.baseName(buildfile_path);
	auto buildfile_contents = std.file.readText(buildfile_path);

	// configure build host
	auto build_host_options = WoxBuilder.Options.init;
	build_host_options.graphviz_file = a.option("graphviz_file");
	build_host_options.n_jobs = a.option("jobs").to!int;
	build_host_options.enable_cache = a.flag("cache");
	build_host_options.list_targets = a.flag("list_targets");
	build_host_options.dry_run = a.flag("dry_run");

	// run build in host
	auto host = new WoxBuilder(log, build_host_options);
	auto build_targets = a.args("targets");
	auto build_success = host.build(
		buildfile_basename, buildfile_contents, build_targets, workdir, buildfile_args, env_vars
	);

	if (!build_success) {
		log.error("build failed");
		return 1;
	}

	return 0;
}
