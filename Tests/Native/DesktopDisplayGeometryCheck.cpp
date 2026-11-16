/** @file DesktopDisplayGeometryCheck.cpp
 * @brief Check capture metadata for the same logical desktop used by mouse delivery.
 */
#include <cstdio>
#include "platform/macos/display_geometry.h"
struct Capture {
  int width, height;
  int offset_x = 0, offset_y = 0, logical_width = 0, logical_height = 0;
  int env_width = 0, env_height = 0, env_logical_width = 0, env_logical_height = 0;
};
int main() {
  const CGRect main = {{0, 0}, {1512, 982}};
  const CGRect left = {{-1920, 0}, {1920, 1080}};
  Capture retina {3024, 1964};
  platf::apply_macos_input_geometry(retina, main, {main, left});
  if (retina.offset_x != 1920 || retina.offset_y != 0 || retina.logical_width != 1512 ||
      retina.logical_height != 982 || retina.env_logical_width != 3432 || retina.env_logical_height != 1080 ||
      retina.env_width != 6864 || retina.env_height != 2160) { return 1; }
  Capture external {1920, 1080};
  platf::apply_macos_input_geometry(external, left, {main, left});
  if (external.offset_x != 0 || external.offset_y != 0 || external.logical_width != 1920 ||
      external.env_logical_width != 3432 || external.env_logical_height != 1080) { return 2; }
  const CGRect above = {{0, -1200}, {1920, 1200}};
  platf::apply_macos_input_geometry(retina, main, {main, above});
  if (retina.offset_y != 1200 || retina.env_logical_height != 2182) { return 3; }
  platf::apply_macos_input_geometry(retina, main, {});
  if (retina.offset_x != 0 || retina.offset_y != 0 || retina.env_logical_width != 1512 ||
      retina.env_logical_height != 982) { return 4; }
  std::puts("PASS: capture offsets, Retina/native units, negative origins and enumeration fallback");
}
