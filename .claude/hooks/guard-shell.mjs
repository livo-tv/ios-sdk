#!/usr/bin/env node
/**
 * Claude Code PreToolUse (Bash). Denies hook bypasses, force-pushes,
 * direct pushes to dev/main (except the ADR 0026 fold), deploys, and bad PR bases.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { commandWorkdir, ghPrInvocation, inspectShell, prDecision } from "./policy.mjs";
import { deny, readHookInput } from "./run.mjs";

function git(cwd, args) {
	const r = spawnSync("git", args, { cwd, encoding: "utf8", windowsHide: true });
	if (r.status !== 0) return "";
	return (r.stdout || "").trim();
}

export function isDevFold(cwd) {
	const head = git(cwd, ["rev-parse", "HEAD"]);
	const main = git(cwd, ["rev-parse", "origin/main"]);
	if (!head || !main) return false;
	if (head === main) return true;
	const ahead = git(cwd, ["rev-list", "--parents", "origin/dev..HEAD"]);
	if (!ahead) return false;
	return ahead.split("\n").every((line) => {
		const parts = line.trim().split(/\s+/);
		return parts.length >= 3 && parts.includes(main);
	});
}

function repoMeta(cwd) {
	const path = resolve(cwd, ".claude/hooks/livo-repo.json");
	if (!existsSync(path)) return { hasDev: true };
	try {
		return JSON.parse(readFileSync(path, "utf8"));
	} catch {
		return { hasDev: true };
	}
}

export async function main() {
	const input = await readHookInput();
	const command = input?.tool_input?.command || "";
	if (!command) return;
	const baseCwd = input.cwd || process.cwd();
	const probed = inspectShell(command, {});
	const work = commandWorkdir(baseCwd, command);
	const cwd = probed.dashC ? resolve(work, probed.dashC) : work;
	const branch = git(cwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
	const shell = inspectShell(command, { currentBranch: branch, foldOk: isDevFold(cwd) });
	if (shell.deny) deny(shell.deny);
	const pr = ghPrInvocation(command);
	if (!pr) return;
	const reason = prDecision({
		action: pr.action,
		base: pr.base,
		head: branch,
		hasDev: repoMeta(cwd).hasDev !== false,
	});
	if (reason) deny(reason);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
	main().catch(() => {
		process.stdout.write("{}");
	});
}
