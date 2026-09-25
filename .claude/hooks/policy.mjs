/**
 * Pure decisions for the Claude Code guards and the shared stop hook.
 * Hook entrypoints in this folder call these; tests import them directly.
 */

import { createHash } from "node:crypto";

export const PROTECTED_BRANCHES = new Set(["dev", "main", "master"]);

/** Literal deny rules. The guard scripts also catch `git -C` / env-prefix forms. */
export const CLAUDE_DENY = [
	"Bash(wrangler deploy *)",
	"Bash(wrangler versions upload *)",
	"Bash(npx wrangler deploy *)",
	"Bash(npx wrangler versions upload *)",
	"Bash(pnpm deploy *)",
	"Bash(pnpm run deploy *)",
	"Bash(pnpm run deploy:dev *)",
	"Bash(pnpm run deploy:prod *)",
	"Bash(pnpm run preview:upload *)",
	"Bash(pnpm publish *)",
	"Bash(npm publish *)",
	"Bash(modal deploy *)",
	"Bash(git push --force *)",
	"Bash(git push -f *)",
	"Bash(git push --force-with-lease *)",
	"Bash(git commit --no-verify *)",
	"Bash(git commit -n *)",
	"Bash(gh pr merge *)",
];

const COMMAND_DESCRIPTIONS = {
	"promote.md": "Promote dev into main with a merge commit, then fold main back",
	"update-context.md": "Update AGENTS.md Learnings and harness docs after a durable change",
	"verify-e2e.md": "Run the e2e spec for the area this change touched",
};

export function mdcToClaudeRule(source) {
	return source.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n*/, "");
}

export function claudeCommand(name, body) {
	const description = COMMAND_DESCRIPTIONS[name] || "Livo harness command";
	return `---\ndescription: ${description}\n---\n\n${body.trim()}\n`;
}

export function claudeSettings() {
	const node = (script, timeout) => ({
		type: "command",
		command: `node "\${CLAUDE_PROJECT_DIR}/.claude/hooks/${script}"`,
		timeout,
	});
	return {
		permissions: { deny: CLAUDE_DENY },
		hooks: {
			PreToolUse: [
				{
					matcher: "Bash",
					hooks: [node("guard-shell.mjs", 30), node("gate-before-publish.mjs", 600)],
				},
				{
					matcher: "Edit|Write",
					hooks: [node("guard-edit.mjs", 20)],
				},
			],
			Stop: [{ hooks: [node("context-upkeep.mjs", 20)] }],
			SessionStart: [{ hooks: [node("session-start.mjs", 20)] }],
		},
	};
}

export function splitCompound(command) {
	const parts = [];
	let cur = "";
	let quote = null;
	for (let i = 0; i < command.length; i++) {
		const c = command[i];
		if (quote) {
			cur += c;
			if (c === quote && command[i - 1] !== "\\") quote = null;
			continue;
		}
		if (c === "'" || c === '"') {
			quote = c;
			cur += c;
			continue;
		}
		if (command.startsWith("&&", i) || command.startsWith("||", i)) {
			parts.push(cur);
			cur = "";
			i += 1;
			continue;
		}
		if (c === ";" || c === "\n" || (c === "|" && command[i + 1] !== "|")) {
			parts.push(cur);
			cur = "";
			continue;
		}
		cur += c;
	}
	if (cur.trim()) parts.push(cur);
	return parts.map((s) => s.trim()).filter(Boolean);
}

function stripWrappers(segment) {
	let s = segment.trim();
	const env = /^(?:[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|"[^"]*"|\S+)\s+)+/;
	const wrap =
		/^(?:timeout\s+\d+\s+|time\s+|nice(?:\s+-n\s+\d+)?\s+|nohup\s+|command\s+|builtin\s+|noglob\s+)/;
	for (let n = 0; n < 6; n++) {
		const next = s.replace(env, "").replace(wrap, "");
		if (next === s) break;
		s = next.trim();
	}
	return s;
}

export function tokenize(segment) {
	const tokens = [];
	let cur = "";
	let quote = null;
	const s = stripWrappers(segment);
	for (let i = 0; i < s.length; i++) {
		const c = s[i];
		if (quote) {
			if (c === quote) quote = null;
			else cur += c;
			continue;
		}
		if (c === "'" || c === '"') {
			quote = c;
			continue;
		}
		if (/\s/.test(c)) {
			if (cur) tokens.push(cur);
			cur = "";
			continue;
		}
		cur += c;
	}
	if (cur) tokens.push(cur);
	return tokens;
}

function gitInvocation(tokens) {
	if (tokens[0] !== "git") return null;
	let i = 1;
	let dashC = null;
	while (i < tokens.length && tokens[i].startsWith("-")) {
		const t = tokens[i];
		if (
			t === "-C" ||
			t === "-c" ||
			t === "--git-dir" ||
			t === "--work-tree" ||
			t === "--namespace"
		) {
			if (t === "-C") dashC = tokens[i + 1] || null;
			i += 2;
			continue;
		}
		if (t.startsWith("-C") && t.length > 2) {
			dashC = t.slice(2);
			i += 1;
			continue;
		}
		if (
			t.startsWith("--git-dir=") ||
			t.startsWith("--work-tree=") ||
			t.startsWith("--namespace=") ||
			t.startsWith("-c")
		) {
			i += 1;
			continue;
		}
		i += 1;
	}
	if (i >= tokens.length) return null;
	return { sub: tokens[i], args: tokens.slice(i + 1), dashC };
}

function normalizeRef(spec, currentBranch) {
	const dst = spec.includes(":") ? spec.slice(spec.lastIndexOf(":") + 1) : spec;
	const name = dst.replace(/^\+/, "").replace(/^refs\/heads\//, "");
	if (name === "HEAD") return currentBranch || "HEAD";
	return name;
}

function pushPlan(args, currentBranch) {
	const valued = new Set(["-o", "--push-option", "--receive-pack", "--exec", "--repo"]);
	const positionals = [];
	let force = false;
	let all = false;
	for (let i = 0; i < args.length; i++) {
		const a = args[i];
		if (a === "--") {
			positionals.push(...args.slice(i + 1));
			break;
		}
		if (
			a === "--force" ||
			a === "-f" ||
			a === "--force-with-lease" ||
			a.startsWith("--force-with-lease") ||
			/^-[^-]*f/.test(a)
		) {
			force = true;
		}
		if (a === "--all" || a === "--mirror") all = true;
		if (a.startsWith("-")) {
			if (valued.has(a)) i += 1;
			continue;
		}
		positionals.push(a);
	}
	let refs = positionals;
	if (
		positionals.length > 1 &&
		!positionals[0].includes(":") &&
		positionals[0] !== "HEAD" &&
		!positionals[0].startsWith("refs/")
	) {
		refs = positionals.slice(1);
	} else if (
		positionals.length === 1 &&
		!positionals[0].includes(":") &&
		positionals[0] !== "HEAD" &&
		!positionals[0].startsWith("refs/")
	) {
		refs = [];
	}
	const dests = refs.length
		? refs.map((spec) => normalizeRef(spec, currentBranch))
		: [currentBranch || ""];
	return { force, all, dests: dests.filter(Boolean) };
}

function isDeploy(tokens) {
	const [a, b, c] = tokens;
	if (a === "wrangler" && (b === "deploy" || (b === "versions" && c === "upload"))) return true;
	if (a === "npx" && tokens.includes("wrangler")) {
		if (tokens.includes("deploy")) return true;
		const v = tokens.indexOf("versions");
		if (v >= 0 && tokens[v + 1] === "upload") return true;
	}
	if ((a === "pnpm" || a === "npm") && b === "publish") return true;
	if (a === "pnpm" && b === "deploy") return true;
	if (a === "pnpm" && b === "run" && (c === "deploy" || c === "deploy:dev" || c === "deploy:prod"))
		return true;
	if (a === "pnpm" && b === "run" && c === "preview:upload") return true;
	if (a === "modal" && b === "deploy") return true;
	if (tokens.some((t) => t.includes("publishToMavenCentral"))) return true;
	if (tokens.some((t) => t.endsWith("preview-stack.mjs") || t.endsWith("preview-upload.mjs")))
		return true;
	if ((a === "npm" || a === "pnpm" || a === "yarn") && b === "version") return true;
	return false;
}

function commitSkipsHooks(args) {
	return args.some((a) => a === "--no-verify" || a === "-n" || /^-[^-]*n[^-]*$/.test(a));
}

/**
 * @param {string} command
 * @param {{ currentBranch?: string, foldOk?: boolean }} [ctx]
 * @returns {{ deny: string | null, publish: boolean, dashC: string | null }}
 */
export function inspectShell(command, ctx = {}) {
	const raw = String(command || "");
	if (/(^|[\s;&|])HUSKY=0(\s|$)/.test(raw)) {
		return {
			deny: "Do not bypass git hooks (HUSKY=0). Commitlint and the quality gate depend on them.",
			publish: false,
			dashC: null,
		};
	}
	let deny = null;
	let publish = false;
	let dashC = null;
	for (const segment of splitCompound(raw)) {
		if (/^cd\s+/.test(segment)) continue;
		const tokens = tokenize(segment);
		if (!tokens.length) continue;
		if (tokens.join(" ").includes("core.hooksPath")) {
			deny = "Do not change core.hooksPath. Husky (or media-engine .githooks) must stay installed.";
		}
		if (isDeploy(tokens)) {
			deny =
				"Do not deploy or publish from an agent. CI (Workers Builds, release workflows, Play, TestFlight, Maven) ships this.";
		}
		const git = gitInvocation(tokens);
		if (git?.dashC) dashC = git.dashC;
		if (git?.sub === "commit" && commitSkipsHooks(git.args)) {
			deny = "Do not skip commit hooks (--no-verify). Fix the commit message or the gate.";
		}
		if (git?.sub === "push") {
			const plan = pushPlan(git.args, ctx.currentBranch);
			const protectedDest = plan.dests.filter((d) => PROTECTED_BRANCHES.has(d));
			const onlyDevFold =
				ctx.foldOk && protectedDest.length > 0 && protectedDest.every((d) => d === "dev");
			if (plan.force) deny = "Do not force-push.";
			else if (plan.all || (protectedDest.length > 0 && !onlyDevFold)) {
				deny =
					"Do not push directly to dev or main. Push a working branch. The dev ← main fold (fast-forward, or a merge of origin/main) is the only direct push to dev.";
			}
		}
		if (tokens[0] === "gh" && tokens[1] === "pr" && tokens[2] === "merge") {
			deny =
				"Agents do not merge pull requests. A human merges. Promotes use a merge commit, never squash.";
		}
		if (
			git?.sub === "push" ||
			(tokens[0] === "gh" && tokens[1] === "pr" && tokens[2] === "create")
		) {
			publish = true;
		}
	}
	return { deny, publish, dashC };
}

export function ghPrInvocation(command) {
	for (const segment of splitCompound(String(command || ""))) {
		const tokens = tokenize(segment);
		if (tokens[0] !== "gh" || tokens[1] !== "pr") continue;
		const action = tokens[2] || "";
		let base = null;
		for (let i = 3; i < tokens.length; i++) {
			const a = tokens[i];
			if (a === "--base" || a === "-B") {
				base = tokens[i + 1] || null;
				i += 1;
				continue;
			}
			if (a.startsWith("--base=")) base = a.slice("--base=".length);
		}
		return { action, base };
	}
	return null;
}

/**
 * @param {{ action: string, base: string | null, head: string, hasDev: boolean }} args
 */
export function prDecision({ action, base, head, hasDev }) {
	if (action === "merge") {
		return "Agents do not merge pull requests. A human merges. Promotes use a merge commit, never squash.";
	}
	if (action !== "create") return null;
	const hotfix = /^hotfix[/-]/.test(head || "");
	const promote = head === "dev";
	if (!hasDev) {
		if (base && base !== "main") return "This repo has no dev branch. Open the PR into main.";
		return null;
	}
	if (promote) {
		if (base !== "main") return "A promote PR (head dev) must pass --base main.";
		return null;
	}
	if (hotfix) {
		if (base !== "main") return "A hotfix PR must use a hotfix/* branch and --base main.";
		return null;
	}
	if (base !== "dev") {
		return "Product PRs target dev. Pass --base dev (a hotfix uses hotfix/* and --base main; a promote has head dev).";
	}
	return null;
}

const VERSION_RES = [
	/"version"\s*:\s*"[^"]*"/,
	/^version\s*=\s*"[^"]*"/m,
	/MARKETING_VERSION\s*=\s*\S+/,
	/(?:^|\n)VERSION_NAME\s*=\s*\S+/,
	/LIVO_VERSION_NAME\s*=\s*\S+/,
];

function versionFingerprints(text) {
	return VERSION_RES.map((re) => (String(text).match(re) || [])[0] || "").join("\n");
}

export function versionEditDenied(filePath, oldText, newText) {
	const base = String(filePath || "")
		.split(/[/\\]/)
		.pop();
	const watched =
		base === "package.json" ||
		base === "pyproject.toml" ||
		base === "gradle.properties" ||
		base === "Info.plist" ||
		(base || "").endsWith(".pbxproj");
	if (base === "package.json") {
		try {
			const a = JSON.parse(oldText);
			const b = JSON.parse(newText);
			if (a && b && typeof a.version === "string" && a.version !== b.version) return true;
			if (a && b && typeof a.version === "string") return false;
		} catch {
			/* snippet, fall through */
		}
	}
	if (!watched) return false;
	const before = versionFingerprints(oldText);
	const after = versionFingerprints(newText);
	return before !== after && (before.trim() !== "" || after.trim() !== "");
}

export function isGeneratedAgentPath(filePath) {
	const p = String(filePath || "").replace(/\\/g, "/");
	if (/\/\.cursor\/(rules|commands|hooks)(\/|$)/.test(p)) return true;
	if (p.endsWith("/.cursor/hooks.json") || p.endsWith("/.cursor/hooks.jsonc")) return true;
	if (/\/\.claude\//.test(p)) return true;
	if (/(^|\/)CLAUDE\.md$/.test(p)) return true;
	return false;
}

export function touchesManagedBlock(oldText, newText) {
	const blob = `${oldText || ""}\n${newText || ""}`;
	return blob.includes("harness:begin managed") || blob.includes("harness:end managed");
}

export function editDenied(filePath, chunks) {
	if (isGeneratedAgentPath(filePath)) {
		return "That file is generated from the harness. Edit the harness source and run sync.mjs.";
	}
	if (
		String(filePath || "")
			.replace(/\\/g, "/")
			.endsWith("AGENTS.md") &&
		chunks.some((c) => touchesManagedBlock(c.old, c.neu))
	) {
		return "The managed AGENTS.md block is generated. Edit ## Learnings, or change the harness source and run sync.mjs.";
	}
	if (chunks.some((c) => versionEditDenied(filePath, c.old, c.neu))) {
		return "Do not hand-bump versions. semantic-release owns package.json, pyproject.toml, MARKETING_VERSION, and VERSION_NAME.";
	}
	return null;
}

export function contextStopPayload({ claude, stopHookActive, needsFollowup, message }) {
	if (stopHookActive) return {};
	if (!needsFollowup) return {};
	if (claude) return { decision: "block", reason: message };
	return { followup_message: message };
}

export function upkeepMessage(hits) {
	const shown = hits.slice(0, 8).join(", ");
	const more = hits.length > 8 ? ` (+${hits.length - 8} more)` : "";
	return (
		`Contract-bearing paths changed without AGENTS.md/harness updates: ${shown}${more}. ` +
		"Run /update-context (or edit ## Learnings / harness/platform) before finishing."
	);
}

export function sessionNotes({ branch, hooksPath, hasHusky, hasGitHooks, depsInstalled }) {
	const notes = [];
	if (branch === "dev" || branch === "main") {
		notes.push(
			`HEAD is ${branch}. Product work goes on a branch from origin/dev with the PR into dev. Harness stays on main. A hotfix uses a hotfix/* branch into main.`,
		);
	}
	if (hasHusky && hooksPath !== ".husky/_" && hooksPath !== ".husky") {
		notes.push(
			`Git hooks are not installed (core.hooksPath=${hooksPath || "unset"}). Run pnpm install so prepare can set Husky.`,
		);
	}
	if (hasGitHooks && hooksPath !== ".githooks") {
		notes.push(
			`media-engine hooks are not installed (core.hooksPath=${hooksPath || "unset"}). Run python scripts/install-hooks.py.`,
		);
	}
	if (depsInstalled === false) {
		notes.push("Dependencies are not installed. Run pnpm install before the quality gate.");
	}
	return notes;
}

export function publishDecision({ publish, mobileRemindOnly, cacheHit, gateExitCode }) {
	if (!publish) return { action: "ignore" };
	if (mobileRemindOnly) {
		return {
			action: "remind",
			message:
				"Android/iOS quality gate is remind-only here. Run ./scripts/ci-check.sh on a machine that can build before you treat this as done.",
		};
	}
	if (cacheHit) return { action: "allow" };
	if (gateExitCode !== 0) {
		return {
			action: "deny",
			message: "The repo quality gate failed. Fix it before git push or gh pr create.",
		};
	}
	return { action: "allow", writeCache: true };
}

export function cacheKey(head, porcelain, diffText) {
	if (!String(porcelain || "").trim()) return head;
	const hash = createHash("sha256")
		.update(String(diffText || ""))
		.digest("hex")
		.slice(0, 16);
	return `${head}:${hash}`;
}

export function commandWorkdir(cwd, command) {
	const first = splitCompound(String(command || ""))[0] || "";
	const match = first.match(/^cd\s+(.+)$/);
	if (!match) return cwd || ".";
	let target = match[1].trim().replace(/^['"]|['"]$/g, "");
	if (!target || target === "-") return cwd || ".";
	if (target.startsWith("/")) return target;
	const base = cwd || ".";
	return `${base.replace(/\/$/, "")}/${target}`;
}
