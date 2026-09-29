#!/usr/bin/env node
/**
 * Re-inject harness rules after context summarization.
 * Cursor: preCompact sets a flag; the next postToolUse returns
 * additional_context (preCompact cannot). Claude Code: SessionStart
 * source=compact returns additionalContext. Both record reads of
 * skills, commands, harness/platform docs, and .mdc files.
 * Fails open. State stays in the OS temp dir.
 */
import {
	appendFileSync,
	mkdirSync,
	readdirSync,
	readFileSync,
	statSync,
	unlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { compactionRow, rehydrateStep } from "./policy.mjs";

const DIR = join(tmpdir(), "livo-harness");
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

export function stateFile(id) {
	const safe = String(id || "")
		.replace(/[^A-Za-z0-9_-]/g, "")
		.slice(0, 80);
	return join(DIR, `${safe || "unknown"}.json`);
}

function loadState(id) {
	try {
		const parsed = JSON.parse(readFileSync(stateFile(id), "utf8"));
		if (!parsed || typeof parsed !== "object") return emptyState();
		return {
			reads: Array.isArray(parsed.reads) ? parsed.reads : [],
			compacted: Boolean(parsed.compacted),
		};
	} catch {
		return emptyState();
	}
}

function emptyState() {
	return { reads: [], compacted: false };
}

function saveState(id, state) {
	mkdirSync(DIR, { recursive: true });
	writeFileSync(stateFile(id), JSON.stringify(state));
	prune();
}

function prune() {
	let names;
	try {
		names = readdirSync(DIR);
	} catch {
		return;
	}
	const now = Date.now();
	for (const name of names) {
		if (!name.endsWith(".json")) continue;
		const path = join(DIR, name);
		try {
			if (now - statSync(path).mtimeMs > MAX_AGE_MS) unlinkSync(path);
		} catch {
			// A locked or missing file is not a reason to fail the hook.
		}
	}
}

function logCompaction(input) {
	mkdirSync(DIR, { recursive: true });
	appendFileSync(
		join(DIR, "compactions.jsonl"),
		`${JSON.stringify(compactionRow(input))}\n`,
	);
}

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

export async function handleRehydrate(input) {
	const event = String(input?.hook_event_name || "");
	if (!event) return {};
	const id = input.conversation_id || input.session_id || "unknown";
	if (event === "preCompact" || event === "PreCompact") {
		try {
			logCompaction(input);
		} catch {
			// The reminder still matters if the log cannot be written.
		}
	}
	const current = loadState(id);
	const step = rehydrateStep(current, input);
	if (JSON.stringify(step.state) !== JSON.stringify(current)) {
		try {
			saveState(id, step.state);
		} catch {
			// Inject the reminder even when the temp dir is not writable.
		}
	}
	return step.output;
}

async function main() {
	const input = await readStdin();
	let output = {};
	try {
		output = await handleRehydrate(input);
	} catch {
		output = {};
	}
	process.stdout.write(JSON.stringify(output));
}

if (
	process.argv[1] &&
	fileURLToPath(import.meta.url) === resolve(process.argv[1])
) {
	main();
}
