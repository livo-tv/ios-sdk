/** Shared stdin / deny helpers for Claude Code command hooks. */

export async function readHookInput() {
	const chunks = [];
	for await (const c of process.stdin) chunks.push(c);
	const raw = Buffer.concat(chunks).toString("utf8").trim();
	if (!raw) return {};
	try {
		return JSON.parse(raw);
	} catch {
		return {};
	}
}

export function deny(reason) {
	const payload = {
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason: reason,
		},
	};
	process.stdout.write(JSON.stringify(payload));
	process.stderr.write(`${reason}\n`);
	process.exit(2);
}

export function allow(message) {
	if (message) process.stdout.write(JSON.stringify({ systemMessage: message }));
	process.exit(0);
}
