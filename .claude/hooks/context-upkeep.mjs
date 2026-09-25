#!/usr/bin/env node
/**
 * Stop hook for Cursor and Claude Code.
 * When contract-bearing paths changed and AGENTS.md / harness docs did not,
 * Cursor gets followup_message and Claude Code gets decision:block (once).
 * Fails open.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { contextStopPayload, upkeepMessage } from "./policy.mjs";

const CONTRACT_RE =
	/(wrangler[^/]*\.jsonc$|prisma\/schema\.prisma$|src\/routes\/|src\/endpoints\/|package\.json$)/i;
const CONTEXT_RE = /(AGENTS\.md$|(^|\/)platform\/|(^|\/)registry\/)/i;

function readStdin() {
	return new Promise((resolveIn) => {
		const chunks = [];
		process.stdin.on("data", (c) => chunks.push(c));
		process.stdin.on("end", () => {
			const raw = Buffer.concat(chunks).toString("utf8").trim();
			if (!raw) return resolveIn({});
			try {
				resolveIn(JSON.parse(raw));
			} catch {
				resolveIn({});
			}
		});
		process.stdin.on("error", () => resolveIn({}));
	});
}

function gitStatus(cwd) {
	if (!existsSync(join(cwd, ".git"))) return [];
	const r = spawnSync("git", ["status", "--porcelain"], {
		cwd,
		encoding: "utf8",
		windowsHide: true,
	});
	if (r.status !== 0) return [];
	return (r.stdout || "")
		.split("\n")
		.map((l) => l.trimEnd())
		.filter(Boolean)
		.map((l) => l.slice(3).replace(/ -> /, " ").split(" ").pop());
}

export function scriptRoot() {
	return dirname(dirname(dirname(fileURLToPath(import.meta.url))));
}

function scanTargets(root) {
	if (existsSync(join(root, ".git"))) return [{ name: "", cwd: root }];
	return readdirSync(root, { withFileTypes: true })
		.filter((d) => d.isDirectory() && !d.name.startsWith(".") && d.name !== "node_modules")
		.filter((d) => existsSync(join(root, d.name, ".git")))
		.map((d) => ({ name: d.name, cwd: join(root, d.name) }));
}

export function findUpkeepHits(root) {
	const contractHits = [];
	const contextHits = [];
	for (const target of scanTargets(root)) {
		for (const file of gitStatus(target.cwd)) {
			const rel = `${target.name ? `${target.name}/` : ""}${file}`.replace(/\\/g, "/");
			if (CONTRACT_RE.test(rel)) contractHits.push(rel);
			if (CONTEXT_RE.test(rel)) contextHits.push(rel);
		}
	}
	return { contractHits, contextHits };
}

async function main() {
	const input = await readStdin();
	const claude = input.hook_event_name === "Stop" || typeof input.stop_hook_active === "boolean";
	const { contractHits, contextHits } = findUpkeepHits(scriptRoot());
	const payload = contextStopPayload({
		claude,
		stopHookActive: Boolean(input.stop_hook_active),
		needsFollowup: contractHits.length > 0 && contextHits.length === 0,
		message: upkeepMessage(contractHits),
	});
	process.stdout.write(JSON.stringify(payload));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
	main().catch(() => {
		process.stdout.write("{}");
	});
}
