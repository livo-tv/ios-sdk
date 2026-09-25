#!/usr/bin/env node
/**
 * Claude Code SessionStart. Warns when hooks are missing, dependencies are
 * not installed, or HEAD is dev/main. Prints plain text; Claude Code adds
 * SessionStart stdout to the conversation.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { sessionNotes } from "./policy.mjs";

function git(cwd, args) {
	const r = spawnSync("git", args, {
		cwd,
		encoding: "utf8",
		windowsHide: true,
	});
	if (r.status !== 0) return "";
	return (r.stdout || "").trim();
}

export function notesForRepo(repo) {
	if (!existsSync(resolve(repo, ".git"))) return [];
	const branch = git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]);
	const hooksPath = git(repo, ["config", "--get", "core.hooksPath"]);
	const hasHusky = existsSync(resolve(repo, ".husky"));
	const hasGitHooks = existsSync(resolve(repo, ".githooks"));
	const needsInstall =
		existsSync(resolve(repo, "package.json")) &&
		!existsSync(resolve(repo, "node_modules"));
	return sessionNotes({
		branch,
		hooksPath,
		hasHusky,
		hasGitHooks,
		depsInstalled: needsInstall ? false : true,
	});
}

function scriptRoot() {
	return dirname(dirname(dirname(fileURLToPath(import.meta.url))));
}

function repos(root) {
	if (existsSync(resolve(root, ".git"))) return [root];
	return readdirSync(root, { withFileTypes: true })
		.filter(
			(d) =>
				d.isDirectory() &&
				!d.name.startsWith(".") &&
				existsSync(resolve(root, d.name, ".git")),
		)
		.map((d) => resolve(root, d.name));
}

export function main() {
	const lines = [];
	for (const repo of repos(scriptRoot())) {
		for (const note of notesForRepo(repo)) lines.push(note);
	}
	if (lines.length) process.stdout.write(`${lines.join("\n")}\n`);
}

if (
	process.argv[1] &&
	fileURLToPath(import.meta.url) === resolve(process.argv[1])
) {
	try {
		main();
	} catch {
		process.stdout.write("");
	}
}
