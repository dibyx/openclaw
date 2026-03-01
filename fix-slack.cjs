const fs = require("fs");

const path = "src/slack/monitor/provider.ts";
let content = fs.readFileSync(path, "utf8");

content = content.replace(
  /\(slackBoltModule as any\)/g,
  "(slackBoltModule as { default?: { App?: unknown } })",
);

fs.writeFileSync(path, content);
