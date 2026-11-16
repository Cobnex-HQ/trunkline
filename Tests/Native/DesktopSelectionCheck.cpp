/** @file DesktopSelectionCheck.cpp
 * @brief Verify identity-based display selection across requests and topology changes.
 */
#include <cstdio>
#include "display_selection.h"
int main() {
  video::DisplaySelection selection;
  const std::vector<std::string> initial {"main", "left", "upper"};
  if (selection.request("missing", initial) || selection.request("", initial)) { return 1; }
  if (!selection.request("left", initial)) { return 2; }
  if (selection.choose({"upper", "main", "left"}, 0) != 2) { return 3; }
  selection.activate("left");
  if (selection.needs_switch() || selection.snapshot().active != "left") { return 4; }
  selection.request("upper", initial);
  if (!selection.needs_switch()) { return 5; }
  selection.request("main", initial);
  selection.activate("upper"); // Completion of an earlier switch must not overwrite the newer request.
  if (!selection.needs_switch() || selection.choose(initial, 2) != 0) { return 6; }
  selection.activate("main");
  if (selection.needs_switch()) { return 7; }
  selection.request("left", initial);
  if (selection.choose({"main", "upper"}, 0) != 0) { return 8; }
  const auto missing = selection.snapshot();
  if (missing.error.empty() || missing.preferred.has_value()) { return 9; }
  if (selection.request("invalid", initial) || selection.snapshot().active != "main") { return 10; }
  selection.request("upper", initial);
  if (!selection.snapshot().error.empty()) { return 11; }
  selection.deactivate();
  if (selection.snapshot().active.has_value() || selection.needs_switch()) { return 12; }
  if (selection.choose({"upper", "main"}, 1) != 0) { return 13; }
  if (selection.choose({}, 7) != -1) { return 14; }
  std::puts("PASS: identity selection, reordered/removed displays, superseded requests, idle preference and rejected IDs");
}
