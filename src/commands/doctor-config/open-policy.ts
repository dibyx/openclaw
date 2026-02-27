import type { OpenClawConfig } from "../../config/config.js";

/**
 * Scan all channel configs for dmPolicy="open" without allowFrom including "*".
 * This configuration is rejected by the schema validator but can easily occur when
 * users (or integrations) set dmPolicy to "open" without realising that an explicit
 * allowFrom wildcard is also required.
 */
export function maybeRepairOpenPolicyAllowFrom(cfg: OpenClawConfig): {
  config: OpenClawConfig;
  changes: string[];
} {
  const channels = cfg.channels;
  if (!channels || typeof channels !== "object") {
    return { config: cfg, changes: [] };
  }

  const next = structuredClone(cfg);
  const changes: string[] = [];

  type OpenPolicyAllowFromMode = "topOnly" | "topOrNested" | "nestedOnly";

  const resolveAllowFromMode = (channelName: string): OpenPolicyAllowFromMode => {
    if (channelName === "googlechat") {
      return "nestedOnly";
    }
    if (channelName === "discord" || channelName === "slack") {
      return "topOrNested";
    }
    return "topOnly";
  };

  const hasWildcard = (list?: Array<string | number>) =>
    list?.some((v) => String(v).trim() === "*") ?? false;

  const ensureWildcard = (
    account: Record<string, unknown>,
    prefix: string,
    mode: OpenPolicyAllowFromMode,
  ) => {
    const dmEntry = account.dm;
    const dm =
      dmEntry && typeof dmEntry === "object" && !Array.isArray(dmEntry)
        ? (dmEntry as Record<string, unknown>)
        : undefined;
    const dmPolicy =
      (account.dmPolicy as string | undefined) ?? (dm?.policy as string | undefined) ?? undefined;

    if (dmPolicy !== "open") {
      return;
    }

    const topAllowFrom = account.allowFrom as Array<string | number> | undefined;
    const nestedAllowFrom = dm?.allowFrom as Array<string | number> | undefined;

    if (mode === "nestedOnly") {
      if (hasWildcard(nestedAllowFrom)) {
        return;
      }
      if (Array.isArray(nestedAllowFrom)) {
        nestedAllowFrom.push("*");
        changes.push(`- ${prefix}.dm.allowFrom: added "*" (required by dmPolicy="open")`);
        return;
      }
      const nextDm = dm ?? {};
      nextDm.allowFrom = ["*"];
      account.dm = nextDm;
      changes.push(`- ${prefix}.dm.allowFrom: set to ["*"] (required by dmPolicy="open")`);
      return;
    }

    if (mode === "topOrNested") {
      if (hasWildcard(topAllowFrom) || hasWildcard(nestedAllowFrom)) {
        return;
      }

      if (Array.isArray(topAllowFrom)) {
        topAllowFrom.push("*");
        changes.push(`- ${prefix}.allowFrom: added "*" (required by dmPolicy="open")`);
      } else if (Array.isArray(nestedAllowFrom)) {
        nestedAllowFrom.push("*");
        changes.push(`- ${prefix}.dm.allowFrom: added "*" (required by dmPolicy="open")`);
      } else {
        account.allowFrom = ["*"];
        changes.push(`- ${prefix}.allowFrom: set to ["*"] (required by dmPolicy="open")`);
      }
      return;
    }

    if (hasWildcard(topAllowFrom)) {
      return;
    }
    if (Array.isArray(topAllowFrom)) {
      topAllowFrom.push("*");
      changes.push(`- ${prefix}.allowFrom: added "*" (required by dmPolicy="open")`);
    } else {
      account.allowFrom = ["*"];
      changes.push(`- ${prefix}.allowFrom: set to ["*"] (required by dmPolicy="open")`);
    }
  };

  const nextChannels = next.channels as Record<string, Record<string, unknown>>;
  for (const [channelName, channelConfig] of Object.entries(nextChannels)) {
    if (!channelConfig || typeof channelConfig !== "object") {
      continue;
    }

    const allowFromMode = resolveAllowFromMode(channelName);

    // Check the top-level channel config
    ensureWildcard(channelConfig, `channels.${channelName}`, allowFromMode);

    // Check per-account configs (e.g. channels.discord.accounts.mybot)
    const accounts = channelConfig.accounts as Record<string, Record<string, unknown>> | undefined;
    if (accounts && typeof accounts === "object") {
      for (const [accountName, accountConfig] of Object.entries(accounts)) {
        if (accountConfig && typeof accountConfig === "object") {
          ensureWildcard(
            accountConfig,
            `channels.${channelName}.accounts.${accountName}`,
            allowFromMode,
          );
        }
      }
    }
  }

  if (changes.length === 0) {
    return { config: cfg, changes: [] };
  }
  return { config: next, changes };
}
