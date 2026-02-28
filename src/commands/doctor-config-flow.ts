import { formatCliCommand } from "../cli/command-format.js";
import type { OpenClawConfig } from "../config/config.js";
import {
  CONFIG_PATH,
  migrateLegacyConfig,
  readConfigFileSnapshot,
} from "../config/config.js";
import { applyPluginAutoEnable } from "../config/plugin-auto-enable.js";
import { note } from "../terminal/note.js";
import { normalizeLegacyConfigValues } from "./doctor-legacy-config.js";
import type { DoctorOptions } from "./doctor-prompter.js";
import { autoMigrateLegacyStateDir } from "./doctor-state-migrations.js";

// Imported from refactored modules
import {
  collectDiscordAccountScopes,
  collectDiscordIdLists,
  maybeRepairDiscordNumericIds,
  scanDiscordNumericIdEntries,
} from "./doctor-config/discord.js";
import {
  collectExecSafeBinScopes,
  maybeRepairExecSafeBinProfiles,
  scanExecSafeBinCoverage,
  scanExecSafeBinTrustedDirHints,
} from "./doctor-config/exec.js";
import { maybeMigrateLegacyConfig } from "./doctor-config/legacy-migration.js";
import {
  maybeRepairLegacyToolsBySenderKeys,
  scanLegacyToolsBySenderKeys,
} from "./doctor-config/legacy-tools.js";
import { scanMutableAllowlistEntries } from "./doctor-config/mutable-allowlist.js";
import {
  noteIncludeConfinementWarning,
  noteOpencodeProviderOverrides,
} from "./doctor-config/notes.js";
import { maybeRepairOpenPolicyAllowFrom } from "./doctor-config/open-policy.js";
import {
  maybeRepairTelegramAllowFromUsernames,
  scanTelegramAllowFromUsernameEntries,
} from "./doctor-config/telegram.js";
import { stripUnknownConfigKeys } from "./doctor-config/utils.js";

export async function loadAndMaybeMigrateDoctorConfig(params: {
  options: DoctorOptions;
  confirm: (p: { message: string; initialValue: boolean }) => Promise<boolean>;
}) {
  const shouldRepair = params.options.repair === true || params.options.yes === true;
  const stateDirResult = await autoMigrateLegacyStateDir({ env: process.env });
  if (stateDirResult.changes.length > 0) {
    note(stateDirResult.changes.map((entry) => `- ${entry}`).join("\n"), "Doctor changes");
  }
  if (stateDirResult.warnings.length > 0) {
    note(stateDirResult.warnings.map((entry) => `- ${entry}`).join("\n"), "Doctor warnings");
  }

  const legacyConfigChanges = await maybeMigrateLegacyConfig();
  if (legacyConfigChanges.length > 0) {
    note(legacyConfigChanges.map((entry) => `- ${entry}`).join("\n"), "Doctor changes");
  }

  let snapshot = await readConfigFileSnapshot();
  const baseCfg = snapshot.config ?? {};
  let cfg: OpenClawConfig = baseCfg;
  let candidate = structuredClone(baseCfg);
  let pendingChanges = false;
  let shouldWriteConfig = false;
  const fixHints: string[] = [];
  if (snapshot.exists && !snapshot.valid && snapshot.legacyIssues.length === 0) {
    note("Config invalid; doctor will run with best-effort config.", "Config");
    noteIncludeConfinementWarning(snapshot);
  }
  const warnings = snapshot.warnings ?? [];
  if (warnings.length > 0) {
    const lines = warnings.map((issue) => `- ${issue.path}: ${issue.message}`).join("\n");
    note(lines, "Config warnings");
  }

  if (snapshot.legacyIssues.length > 0) {
    note(
      snapshot.legacyIssues.map((issue) => `- ${issue.path}: ${issue.message}`).join("\n"),
      "Legacy config keys detected",
    );
    const { config: migrated, changes } = migrateLegacyConfig(snapshot.parsed);
    if (changes.length > 0) {
      note(changes.join("\n"), "Doctor changes");
    }
    if (migrated) {
      candidate = migrated;
      pendingChanges = pendingChanges || changes.length > 0;
    }
    if (shouldRepair) {
      // Legacy migration (2026-01-02, commit: 16420e5b) — normalize per-provider allowlists; move WhatsApp gating into channels.whatsapp.allowFrom.
      if (migrated) {
        cfg = migrated;
      }
    } else {
      fixHints.push(
        `Run "${formatCliCommand("openclaw doctor --fix")}" to apply legacy migrations.`,
      );
    }
  }

  const normalized = normalizeLegacyConfigValues(candidate);
  if (normalized.changes.length > 0) {
    note(normalized.changes.join("\n"), "Doctor changes");
    candidate = normalized.config;
    pendingChanges = true;
    if (shouldRepair) {
      cfg = normalized.config;
    } else {
      fixHints.push(`Run "${formatCliCommand("openclaw doctor --fix")}" to apply these changes.`);
    }
  }

  const autoEnable = applyPluginAutoEnable({ config: candidate, env: process.env });
  if (autoEnable.changes.length > 0) {
    note(autoEnable.changes.join("\n"), "Doctor changes");
    candidate = autoEnable.config;
    pendingChanges = true;
    if (shouldRepair) {
      cfg = autoEnable.config;
    } else {
      fixHints.push(`Run "${formatCliCommand("openclaw doctor --fix")}" to apply these changes.`);
    }
  }

  if (shouldRepair) {
    const repair = await maybeRepairTelegramAllowFromUsernames(candidate);
    if (repair.changes.length > 0) {
      note(repair.changes.join("\n"), "Doctor changes");
      candidate = repair.config;
      pendingChanges = true;
      cfg = repair.config;
    }

    const discordRepair = maybeRepairDiscordNumericIds(candidate);
    if (discordRepair.changes.length > 0) {
      note(discordRepair.changes.join("\n"), "Doctor changes");
      candidate = discordRepair.config;
      pendingChanges = true;
      cfg = discordRepair.config;
    }

    const allowFromRepair = maybeRepairOpenPolicyAllowFrom(candidate);
    if (allowFromRepair.changes.length > 0) {
      note(allowFromRepair.changes.join("\n"), "Doctor changes");
      candidate = allowFromRepair.config;
      pendingChanges = true;
      cfg = allowFromRepair.config;
    }

    const toolsBySenderRepair = maybeRepairLegacyToolsBySenderKeys(candidate);
    if (toolsBySenderRepair.changes.length > 0) {
      note(toolsBySenderRepair.changes.join("\n"), "Doctor changes");
      candidate = toolsBySenderRepair.config;
      pendingChanges = true;
      cfg = toolsBySenderRepair.config;
    }

    const safeBinProfileRepair = maybeRepairExecSafeBinProfiles(candidate);
    if (safeBinProfileRepair.changes.length > 0) {
      note(safeBinProfileRepair.changes.join("\n"), "Doctor changes");
      candidate = safeBinProfileRepair.config;
      pendingChanges = true;
      cfg = safeBinProfileRepair.config;
    }
    if (safeBinProfileRepair.warnings.length > 0) {
      note(safeBinProfileRepair.warnings.join("\n"), "Doctor warnings");
    }
  } else {
    const hits = scanTelegramAllowFromUsernameEntries(candidate);
    if (hits.length > 0) {
      note(
        [
          `- Telegram allowFrom contains ${hits.length} non-numeric entries (e.g. ${hits[0]?.entry ?? "@"}); Telegram authorization requires numeric sender IDs.`,
          `- Run "${formatCliCommand("openclaw doctor --fix")}" to auto-resolve @username entries to numeric IDs (requires a Telegram bot token).`,
        ].join("\n"),
        "Doctor warnings",
      );
    }

    const discordHits = scanDiscordNumericIdEntries(candidate);
    if (discordHits.length > 0) {
      note(
        [
          `- Discord allowlists contain ${discordHits.length} numeric entries (e.g. ${discordHits[0]?.path}=${discordHits[0]?.entry}).`,
          `- Discord IDs must be strings; run "${formatCliCommand("openclaw doctor --fix")}" to convert numeric IDs to quoted strings.`,
        ].join("\n"),
        "Doctor warnings",
      );
    }

    const allowFromScan = maybeRepairOpenPolicyAllowFrom(candidate);
    if (allowFromScan.changes.length > 0) {
      note(
        [
          ...allowFromScan.changes,
          `- Run "${formatCliCommand("openclaw doctor --fix")}" to add missing allowFrom wildcards.`,
        ].join("\n"),
        "Doctor warnings",
      );
    }

    const toolsBySenderHits = scanLegacyToolsBySenderKeys(candidate);
    if (toolsBySenderHits.length > 0) {
      const sample = toolsBySenderHits[0];
      const sampleLabel = sample ? `${sample.pathLabel}.${sample.key}` : "toolsBySender";
      note(
        [
          `- Found ${toolsBySenderHits.length} legacy untyped toolsBySender key${toolsBySenderHits.length === 1 ? "" : "s"} (for example ${sampleLabel}).`,
          "- Untyped sender keys are deprecated; use explicit prefixes (id:, e164:, username:, name:).",
          `- Run "${formatCliCommand("openclaw doctor --fix")}" to migrate legacy keys to typed id: entries.`,
        ].join("\n"),
        "Doctor warnings",
      );
    }

    const safeBinCoverage = scanExecSafeBinCoverage(candidate);
    if (safeBinCoverage.length > 0) {
      const interpreterHits = safeBinCoverage.filter((hit) => hit.isInterpreter);
      const customHits = safeBinCoverage.filter((hit) => !hit.isInterpreter);
      const lines: string[] = [];
      if (interpreterHits.length > 0) {
        for (const hit of interpreterHits.slice(0, 5)) {
          lines.push(
            `- ${hit.scopePath}.safeBins includes interpreter/runtime '${hit.bin}' without profile.`,
          );
        }
        if (interpreterHits.length > 5) {
          lines.push(
            `- ${interpreterHits.length - 5} more interpreter/runtime safeBins entries are missing profiles.`,
          );
        }
      }
      if (customHits.length > 0) {
        for (const hit of customHits.slice(0, 5)) {
          lines.push(
            `- ${hit.scopePath}.safeBins entry '${hit.bin}' is missing safeBinProfiles.${hit.bin}.`,
          );
        }
        if (customHits.length > 5) {
          lines.push(
            `- ${customHits.length - 5} more custom safeBins entries are missing profiles.`,
          );
        }
      }
      lines.push(
        `- Run "${formatCliCommand("openclaw doctor --fix")}" to scaffold missing custom safeBinProfiles entries.`,
      );
      note(lines.join("\n"), "Doctor warnings");
    }

    const safeBinTrustedDirHints = scanExecSafeBinTrustedDirHints(candidate);
    if (safeBinTrustedDirHints.length > 0) {
      const lines = safeBinTrustedDirHints
        .slice(0, 5)
        .map(
          (hit) =>
            `- ${hit.scopePath}.safeBins entry '${hit.bin}' resolves to '${hit.resolvedPath}' outside trusted safe-bin dirs.`,
        );
      if (safeBinTrustedDirHints.length > 5) {
        lines.push(
          `- ${safeBinTrustedDirHints.length - 5} more safeBins entries resolve outside trusted safe-bin dirs.`,
        );
      }
      lines.push(
        "- If intentional, add the binary directory to tools.exec.safeBinTrustedDirs (global or agent scope).",
      );
      note(lines.join("\n"), "Doctor warnings");
    }
  }

  const mutableAllowlistHits = scanMutableAllowlistEntries(candidate);
  if (mutableAllowlistHits.length > 0) {
    const channels = Array.from(new Set(mutableAllowlistHits.map((hit) => hit.channel))).toSorted();
    const exampleLines = mutableAllowlistHits
      .slice(0, 8)
      .map((hit) => `- ${hit.path}: ${hit.entry}`)
      .join("\n");
    const remaining =
      mutableAllowlistHits.length > 8
        ? `- +${mutableAllowlistHits.length - 8} more mutable allowlist entries.`
        : null;
    const flagPaths = Array.from(new Set(mutableAllowlistHits.map((hit) => hit.dangerousFlagPath)));
    const flagHint =
      flagPaths.length === 1
        ? flagPaths[0]
        : `${flagPaths[0]} (and ${flagPaths.length - 1} other scope flags)`;
    note(
      [
        `- Found ${mutableAllowlistHits.length} mutable allowlist ${mutableAllowlistHits.length === 1 ? "entry" : "entries"} across ${channels.join(", ")} while name matching is disabled by default.`,
        exampleLines,
        ...(remaining ? [remaining] : []),
        `- Option A (break-glass): enable ${flagHint}=true to keep name/email/nick matching.`,
        "- Option B (recommended): resolve names/emails/nicks to stable sender IDs and rewrite the allowlist entries.",
      ].join("\n"),
      "Doctor warnings",
    );
  }

  const unknown = stripUnknownConfigKeys(candidate);
  if (unknown.removed.length > 0) {
    const lines = unknown.removed.map((path) => `- ${path}`).join("\n");
    candidate = unknown.config;
    pendingChanges = true;
    if (shouldRepair) {
      cfg = unknown.config;
      note(lines, "Doctor changes");
    } else {
      note(lines, "Unknown config keys");
      fixHints.push('Run "openclaw doctor --fix" to remove these keys.');
    }
  }

  if (!shouldRepair && pendingChanges) {
    const shouldApply = await params.confirm({
      message: "Apply recommended config repairs now?",
      initialValue: true,
    });
    if (shouldApply) {
      cfg = candidate;
      shouldWriteConfig = true;
    } else if (fixHints.length > 0) {
      note(fixHints.join("\n"), "Doctor");
    }
  }

  if (shouldRepair && pendingChanges) {
    shouldWriteConfig = true;
  }

  noteOpencodeProviderOverrides(cfg);

  return {
    cfg,
    path: snapshot.path ?? CONFIG_PATH,
    shouldWriteConfig,
    sourceConfigValid: snapshot.valid,
  };
}
