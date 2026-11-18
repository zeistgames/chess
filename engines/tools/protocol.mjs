// SPDX-License-Identifier: AGPL-3.0-or-later
// Shared by the Node and WebKit checks.

// Every legal reply for Black after 1. e4.
export const LEGAL_AFTER_E4 = new Set([
  "a7a6", "a7a5", "b7b6", "b7b5", "c7c6", "c7c5", "d7d6", "d7d5",
  "e7e6", "e7e5", "f7f6", "f7f5", "g7g6", "g7g5", "h7h6", "h7h5",
  "b8a6", "b8c6", "g8f6", "g8h6",
]);

// Node budget for the check search. Maia has no search: one node is a policy pick.
export function searchNodes(manifest) {
  return manifest.check_nodes || 20000;
}

// UCI lines that set a strength option to the middle of its range.
export function strengthCommands(strength) {
  const mid = Math.round((strength.min + strength.max) / 2);
  if (strength.type === "uci_elo") {
    const lines = [];
    const names = ["UCI_Elo"];
    if (strength.limit !== false) {
      lines.push("setoption name UCI_LimitStrength value true");
      names.push("UCI_LimitStrength");
    }
    lines.push(`setoption name UCI_Elo value ${mid}`);
    return { names, lines };
  }
  if (strength.type === "skill") {
    const name = strength.option || "Skill Level";
    return { names: [name], lines: [`setoption name ${name} value ${mid}`] };
  }
  throw new Error("unknown strength type " + strength.type);
}
