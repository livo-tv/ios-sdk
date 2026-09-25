#!/usr/bin/env node
/**
 * Claude Code PreToolUse (Edit|Write). Blocks generated agent files,
 * managed AGENTS.md blocks, and hand-edited version fields.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { editDenied } from "./policy.mjs";
import { deny, readHookInput } from "./run.mjs";

function chunksFor(input) {
	const tool = input.tool_name || "";
	const args = input.tool_input || {};
	const filePath = args.file_path || args.path || "";
	if (tool === "Write" || args.content != null) {
		const old = existsSync(filePath) ? readFileSync(filePath, "utf8") : "";
		return { filePath, chunks: [{ old, neu: String(args.content ?? "") }] };
	}
	if (Array.isArray(args.edits)) {
		return {
			filePath,
			chunks: args.edits.map((e) => ({
				old: e.old_string || "",
				neu: e.new_string || "",
			})),
		};
	}
	return {
		filePath,
		chunks: [{ old: args.old_string || "", neu: args.new_string || "" }],
	};
}

export async function main() {
	const input = await readHookInput();
	const { filePath, chunks } = chunksFor(input);
	if (!filePath) return;
	const reason = editDenied(filePath, chunks);
	if (reason) deny(reason);
}

if (
	process.argv[1] &&
	fileURLToPath(import.meta.url) === resolve(process.argv[1])
) {
	main().catch(() => {
		process.stdout.write("{}");
	});
}
