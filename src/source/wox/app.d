module wox.app;

import std.stdio;
import std.string;
import std.file;
import std.algorithm;
import std.array;
import std.conv;
import commandr;

import wox.models;

enum DEFAULT_BUILDFILE_NAME = "Woxfile";

int main(string[] args) {
	auto a = new Program("wox", "0.1").summary("A flexible recipe build system inspired by Make")
		.author("redthing1")
		.add(new Argument("targets", "targets to build").repeating.optional)
		.add(new Flag("v", "verbose", "turns on more verbose output").repeating)
		.add(new Option("f", "file", "build file to use")
				.defaultValue(DEFAULT_BUILDFILE_NAME))
		.add(new Option("C", "workdir", "change to this directory before doing anything")
				.defaultValue("."))
		.parse(args);

	auto verbose = min(a.occurencesOf("verbose"), 3);

	// if verbose, dump interpreted arguments
	if (verbose > 0) {
		writefln("invocation: %s", args);
		writefln("  build file: %s", a.option("file"));
		writefln("  targets: %s", a.args("targets"));
	}

	// change to working directory
	auto workdir = a.option("workdir");
	if (!std.file.exists(workdir)) {
		writefln("Error: working directory '%s' does not exist", workdir);
		return 1;
	}

	if (verbose > 0) {
		writefln("changing to working directory '%s'", workdir);
	}

	std.file.chdir(workdir);

	// open build file
	auto buildfile_path = a.option("file");
	if (!std.file.exists(buildfile_path)) {
		writefln("Error: build file '%s' does not exist", buildfile_path);
		return 1;
	}
	auto buildfile_contents = std.file.readText(buildfile_path);
	auto buildfile_model = BuildFile.parse_from_text(buildfile_contents);

	if (verbose > 0) {
		writefln("buildfile:\n%s", buildfile_model);
	}

	return 0;
}
