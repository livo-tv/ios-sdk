#!/usr/bin/env node
/**
 * Claude Code PreToolUse (Bash). Before git push or gh pr create, run the
 * repo quality gate. Android and iOS only remind. A green result is cached
 * per git tree so a push and the following PR do not run it twice.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { cacheKey, commandWorkdir, inspectShell, publishDecision } from "./policy.mjs";
import { allow, deny, readHookInput } from "./run.mjs";

function git(cwd, args) {
	const r = spawnSync("git", args, { cwd, encoding: "utf8", windowsHide: true });
	if (r.status !== 0) return "";
	return r.stdout || "";
}

function metaFor(cwd) {
	const path = resolve(cwd, ".claude/hooks/livo-repo.json");
	if (!existsSync(path)) return null;
	try {
		return JSON.parse(readFileSync(path, "utf8"));
	} catch {
		return null;
	}
}

export async function main() {
	const input = await readHookInput();
	const command = input?.tool_input?.command || "";
	const shell = inspectShell(command, {});
	if (!shell.publish) return;
	const cwd = shell.dashC
		? resolve(commandWorkdir(input.cwd || process.cwd(), command), shell.dashC)
		: commandWorkdir(input.cwd || process.cwd(), command);
	const meta = metaFor(cwd);
	if (!meta?.qualityGate) return;
	const head = git(cwd, ["rev-parse", "HEAD"]).trim();
	const porcelain = git(cwd, ["status", "--porcelain"]);
	const diff = `${git(cwd, ["diff"])}${git(cwd, ["diff", "--cached"])}`;
	const key = cacheKey(head, porcelain, diff);
	const stamp = resolve(cwd, ".git", "livo-gate-ok");
	const cacheHit = existsSync(stamp) && readFileSync(stamp, "utf8").trim() === key;
	if (cacheHit || meta.mobileRemindOnly) {
		const decision = publishDecision({
			publish: true,
			mobileRemindOnly: Boolean(meta.mobileRemindOnly),
			cacheHit,
			gateExitCode: 0,
		});
		if (decision.action === "remind") allow(decision.message);
		return;
	}
	const ran = spawnSync(meta.qualityGate, {
		cwd,
		shell: true,
		encoding: "utf8",
		windowsHide: true,
		timeout: 540000,
	});
	const decision = publishDecision({
		publish: true,
		mobileRemindOnly: false,
		cacheHit: false,
		gateExitCode: ran.status ?? 1,
	});
	if (decision.action === "deny") {
		const tail = `${ran.stdout || ""}\n${ran.stderr || ""}`
			.trim()
			.split("\n")
			.slice(-20)
			.join("\n");
		deny(`${decision.message}\n${tail}`);
	}
	if (decision.writeCache && existsSync(resolve(cwd, ".git"))) {
		writeFileSync(stamp, `${key}\n`);
	}
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
	main().catch(() => {
		process.stdout.write("{}");
	});
}
