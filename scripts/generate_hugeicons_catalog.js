#!/usr/bin/env node
// Extracts path/circle data for a fixed list of HugeIcons (from
// @hugeicons/core-free-icons, the same package RN uses) and prints Swift
// source for Support/HugeIcon.swift. Run once from the repo root:
//   node native/scripts/generate_hugeicons_catalog.js > /tmp/HugeIcon.generated.swift
// then hand-review and fold the `enum HugeIcons { ... }` body into
// Support/HugeIcon.swift. Re-run only if new icons are added later.

const fs = require("fs");
const path = require("path");

const ICON_NAMES = [
  "Add01Icon", "Settings03Icon", "UserMultiple02Icon", "Ticket01Icon",
  "Calendar03Icon", "GridViewIcon", "Wrench02Icon", "Tap03Icon",
  "Cancel01Icon", "CancelCircleIcon", "PencilEdit01Icon", "Tick02Icon",
  "ArrowLeft01Icon", "ArrowRight01Icon", "ArrowUpRight01Icon",
  "Search01Icon", "Delete02Icon", "Share01Icon", "Download04Icon",
  "InstagramIcon", "SquareLock02Icon", "ViewIcon", "ViewOffSlashIcon",
  "Alert01Icon", "QrCodeIcon", "QuoteUpIcon", "CloudUploadIcon",
  "Image01Icon", "UserIcon", "MusicNote01Icon", "Mic01Icon", "Wallet01Icon",
  "PlayCircleIcon", "PauseCircleIcon", "Sun03Icon", "Moon02Icon",
  "PlusSignCircleIcon", "Infinity01Icon", "PlayListIcon", "FavouriteIcon",
  "UserGroup03Icon", "StarCircleIcon", "RadioIcon", "FootballIcon",
  "Invoice01Icon", "CdIcon", "Home05Icon", "MagicWand04Icon",
];

const esmDir = path.join(
  __dirname, "..", "..", "node_modules", "@hugeicons", "core-free-icons", "dist", "esm"
);

function toSwiftName(iconName) {
  const base = iconName.endsWith("Icon") ? iconName.slice(0, -4) : iconName;
  return base.charAt(0).toLowerCase() + base.slice(1);
}

function extractElements(source) {
  const elements = [];
  // Matches ["path", { d: "...", ... }] and ["circle", { cx: "...", cy: "...", r: "...", ... }]
  const entryRe = /\[\s*"(path|circle)"\s*,\s*\{([^}]*)\}\s*\]/g;
  let match;
  while ((match = entryRe.exec(source)) !== null) {
    const [, kind, attrs] = match;
    if (kind === "path") {
      const dMatch = attrs.match(/d:\s*"([^"]*)"/);
      if (!dMatch) throw new Error(`path element with no d attribute: ${attrs}`);
      elements.push({ kind: "path", d: dMatch[1] });
    } else {
      const cx = attrs.match(/cx:\s*"([^"]*)"/);
      const cy = attrs.match(/cy:\s*"([^"]*)"/);
      const r = attrs.match(/r:\s*"([^"]*)"/);
      if (!cx || !cy || !r) throw new Error(`circle element missing cx/cy/r: ${attrs}`);
      elements.push({ kind: "circle", cx: cx[1], cy: cy[1], r: r[1] });
    }
  }
  if (elements.length === 0) throw new Error("no path/circle elements found");
  return elements;
}

function swiftLiteral(elements) {
  const lines = elements.map((el) => {
    if (el.kind === "path") {
      const escaped = el.d.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
      return `      .path("${escaped}")`;
    }
    return `      .circle(cx: ${el.cx}, cy: ${el.cy}, r: ${el.r})`;
  });
  return `[\n${lines.join(",\n")},\n    ]`;
}

const out = [];
out.push("import Foundation");
out.push("");
out.push("/// Auto-extracted from @hugeicons/core-free-icons (the same package RN uses)");
out.push("/// via native/scripts/generate_hugeicons_catalog.js — do not hand-edit path");
out.push("/// data, regenerate instead if an icon needs to change.");
out.push("enum HugeIcons {");

for (const iconName of ICON_NAMES) {
  const filePath = path.join(esmDir, `${iconName}.js`);
  if (!fs.existsSync(filePath)) {
    console.error(`MISSING: ${iconName} (expected at ${filePath})`);
    process.exitCode = 1;
    continue;
  }
  const source = fs.readFileSync(filePath, "utf8");
  const elements = extractElements(source);
  const swiftName = toSwiftName(iconName);
  out.push(`  /// ${iconName}`);
  out.push(`  static let ${swiftName} = HugeIcon(elements: ${swiftLiteral(elements)})`);
  out.push("");
}

out.push("}");

console.log(out.join("\n"));
