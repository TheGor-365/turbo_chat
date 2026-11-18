// Dependency registry advisory feeds may lag or change independently of
// yarn.lock. Fail closed on GHSA-fc5q-39xc-vjpf / CVE-2026-112366 until a
// verified patched picomatch version is available. Do not add ignore flags.
import { readFileSync } from "node:fs";

const lock = readFileSync("yarn.lock", "utf8").split(/\r?\n/);
const found = [];
let inPicomatchBlock = false;
for (const line of lock) {
  if (line.trim() === "") {
    inPicomatchBlock = false;
    continue;
  }
  if (!line.startsWith(" ") && line.endsWith(":")) {
    inPicomatchBlock = line.replaceAll('"', "").startsWith("picomatch@");
    continue;
  }
  if (inPicomatchBlock) {
    const version = line.match(/^  version "(\d+)\.(\d+)\.(\d+)"$/);
    if (version) {
      const [major, minor, patch] = version.slice(1).map(Number);
      if (major < 4 || (major === 4 && minor === 0 && patch <= 7)) {
        found.push(version[0].trim());
      }
    }
  }
}
if (found.length) {
  console.error(
    "::error::Known vulnerable picomatch release(s) remain locked: " +
    found.join("; ") +
    ". GHSA-fc5q-39xc-vjpf / CVE-2026-112366. npm audit zero findings is not a fix."
  );
  process.exitCode = 1;
} else {
  console.log("No locked picomatch release within the documented affected version range.");
}
