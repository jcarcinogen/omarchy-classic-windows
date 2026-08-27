import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
BEGIN_LOADER = "-- BEGIN omarchy-classic-windows"
END_LOADER = "-- END omarchy-classic-windows"
RELOAD_LINE = 'o.launch_on_start("hyprpm reload -n")'
LOADER_LINE = 'local xdg_config = os.getenv("XDG_CONFIG_HOME"); dofile(((xdg_config ~= nil and xdg_config ~= "") and xdg_config or (os.getenv("HOME") .. "/.config")) .. "/hypr/classic-windows.lua")'


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.hypr = self.home / ".config" / "hypr"
        self.hypr.mkdir(parents=True)
        shutil.copy(FIXTURES / "hyprland.lua", self.hypr / "hyprland.lua")
        shutil.copy(FIXTURES / "autostart.lua", self.hypr / "autostart.lua")

        self.omarchy = self.base / "omarchy"
        self.omarchy.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self._write_fake_commands()

        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "OMARCHY_PATH": str(self.omarchy),
                "PATH": f"{self.bin}:{os.environ['PATH']}",
                "NO_COLOR": "1",
            }
        )

    def tearDown(self):
        self.tmp.cleanup()

    def _write_executable(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def _write_fake_commands(self):
        self._write_executable(
            "hyprpm",
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$HOME/hyprpm.log"
case "${1:-}" in
  list)
    if [[ -f "$HOME/.fake-repo-installed" ]]; then
      printf '%s\\n' 'Repository hyprland-plugins (by hyprwm):' '  Plugin hyprbars'
      if [[ -f "$HOME/.fake-hyprbars-enabled" ]]; then
        printf '%s\\n' '  enabled: true'
      else
        printf '%s\\n' '  enabled: false'
      fi
      if [[ -f "$HOME/.fake-other-enabled" ]]; then
        printf '%s\\n' '  Plugin hyprfocus' '  enabled: true'
      fi
    fi
    ;;
  add)
    if [[ "${FAKE_HYPRPM_FAIL_ADD:-}" == "1" ]]; then exit 9; fi
    touch "$HOME/.fake-repo-installed"
    ;;
  enable) touch "$HOME/.fake-hyprbars-enabled" ;;
  disable) rm -f "$HOME/.fake-hyprbars-enabled" ;;
  reload) : ;;
esac
""",
        )
        self._write_executable(
            "hyprctl",
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$HOME/hyprctl.log"
case "${1:-}" in
  version) printf '%s\\n' 'Hyprland 0.56.2' ;;
  configerrors) : ;;
  reload) printf '%s\\n' ok ;;
esac
""",
        )
        self._write_executable("omarchy", "#!/usr/bin/env bash\nexit 0\n")

    def run_script(self, script, *args):
        return subprocess.run(
            ["bash", str(ROOT / script), *args],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_fresh_setup_installs_overlay_and_marked_loader(self):
        result = self.run_script("setup.sh", "--yes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Classic Windows is installed", result.stdout)

        loader = (self.hypr / "hyprland.lua").read_text()
        autostart = (self.hypr / "autostart.lua").read_text()
        overlay = self.hypr / "classic-windows.lua"
        self.assertEqual(loader.count(BEGIN_LOADER), 1)
        self.assertEqual(loader.count(END_LOADER), 1)
        self.assertIn(LOADER_LINE, loader)
        self.assertEqual(autostart.count(RELOAD_LINE), 1)
        self.assertEqual(overlay.read_text(), (ROOT / "config" / "classic-windows.lua").read_text())
        self.assertTrue((self.home / ".fake-hyprbars-enabled").exists())

    def test_setup_explains_global_mode_and_title_bar_maximize(self):
        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Super+Ctrl+T", result.stdout)
        self.assertIn("Double-click the title bar", result.stdout)

    def test_overlay_configures_transparent_bar_and_native_maximize(self):
        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        overlay = (self.hypr / "classic-windows.lua").read_text()
        self.assertIn('bar_color = "rgba(00000000)"', overlay)
        self.assertIn(
            'hl.dsp.window.fullscreen({ mode = \\"maximized\\" })',
            overlay,
        )
        self.assertNotIn("hyprctl dispatch fullscreen 1", overlay)

    def test_overlay_global_mode_is_persistent_and_retiles_only_auto_floats(self):
        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        overlay = (self.hypr / "classic-windows.lua").read_text()
        self.assertIn('hl.unbind("SUPER + CTRL + T")', overlay)
        self.assertIn('o.bind("SUPER + CTRL + T"', overlay)
        self.assertIn('/omarchy-classic-windows/floating-mode.enabled"', overlay)
        self.assertIn('tag = "+cw-auto-float"', overlay)
        self.assertIn('hl.get_windows({ tag = "cw-auto-float" })', overlay)

    def test_setup_is_idempotent(self):
        first = self.run_script("setup.sh", "--yes")
        second = self.run_script("setup.sh", "--yes")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)

        loader = (self.hypr / "hyprland.lua").read_text()
        autostart = (self.hypr / "autostart.lua").read_text()
        self.assertEqual(loader.count(BEGIN_LOADER), 1)
        self.assertEqual(autostart.count(RELOAD_LINE), 1)
        log = (self.home / "hyprpm.log").read_text()
        self.assertEqual(log.count("enable hyprbars"), 1)

    def test_setup_adopts_existing_unmarked_loader_without_duplicates(self):
        hyprland_path = self.hypr / "hyprland.lua"
        autostart_path = self.hypr / "autostart.lua"
        loader = 'dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")'
        hyprland_path.write_text(hyprland_path.read_text() + loader + "\n")
        autostart_path.write_text(autostart_path.read_text() + RELOAD_LINE + "\n")
        (self.hypr / "classic-windows.lua").write_text("-- existing overlay\n")

        setup = self.run_script("setup.sh", "--yes")
        loader_count_after_setup = hyprland_path.read_text().count(loader)
        reload_count_after_setup = autostart_path.read_text().count(RELOAD_LINE)
        uninstall = self.run_script("uninstall.sh", "--yes")

        self.assertEqual(setup.returncode, 0, setup.stdout + setup.stderr)
        self.assertEqual(uninstall.returncode, 0, uninstall.stdout + uninstall.stderr)
        self.assertEqual(loader_count_after_setup, 1)
        self.assertEqual(reload_count_after_setup, 1)
        self.assertEqual(hyprland_path.read_text().count(loader), 1)
        self.assertEqual(autostart_path.read_text().count(RELOAD_LINE), 1)
        self.assertEqual((self.hypr / "classic-windows.lua").read_text(), "-- existing overlay\n")

    def test_commented_loader_and_reload_do_not_count_as_installed(self):
        legacy = 'dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")'
        hyprland_path = self.hypr / "hyprland.lua"
        autostart_path = self.hypr / "autostart.lua"
        hyprland_path.write_text(hyprland_path.read_text() + "-- " + legacy + "\n")
        autostart_path.write_text(autostart_path.read_text() + "-- " + RELOAD_LINE + "\n")

        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(hyprland_path.read_text().count(LOADER_LINE), 1)
        self.assertEqual(hyprland_path.read_text().count("-- " + legacy), 1)
        self.assertEqual(autostart_path.read_text().count(RELOAD_LINE), 2)
        self.assertEqual(autostart_path.read_text().count("\n" + RELOAD_LINE + "\n"), 1)

    def test_setup_enables_hyprbars_when_only_another_plugin_is_enabled(self):
        (self.home / ".fake-repo-installed").touch()
        (self.home / ".fake-other-enabled").touch()

        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".fake-hyprbars-enabled").exists())
        self.assertIn("enable hyprbars", (self.home / "hyprpm.log").read_text())

    def test_plugin_install_failure_does_not_edit_user_configuration(self):
        before_hyprland = (self.hypr / "hyprland.lua").read_text()
        before_autostart = (self.hypr / "autostart.lua").read_text()
        self.env["FAKE_HYPRPM_FAIL_ADD"] = "1"

        result = self.run_script("setup.sh", "--yes")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.hypr / "hyprland.lua").read_text(), before_hyprland)
        self.assertEqual((self.hypr / "autostart.lua").read_text(), before_autostart)
        self.assertFalse((self.hypr / "classic-windows.lua").exists())

    def test_uninstall_restores_preexisting_overlay(self):
        original = "-- my original classic windows file\n"
        (self.hypr / "classic-windows.lua").write_text(original)

        setup = self.run_script("setup.sh", "--yes")
        self.assertEqual(setup.returncode, 0, setup.stdout + setup.stderr)
        self.assertNotEqual((self.hypr / "classic-windows.lua").read_text(), original)

        uninstall = self.run_script("uninstall.sh", "--yes")
        self.assertEqual(uninstall.returncode, 0, uninstall.stdout + uninstall.stderr)
        self.assertIn("Classic Windows has been removed", uninstall.stdout)
        self.assertEqual((self.hypr / "classic-windows.lua").read_text(), original)
        self.assertNotIn(BEGIN_LOADER, (self.hypr / "hyprland.lua").read_text())
        self.assertNotIn(RELOAD_LINE, (self.hypr / "autostart.lua").read_text())

    def test_uninstall_preserves_unrelated_user_configuration(self):
        hyprland_path = self.hypr / "hyprland.lua"
        autostart_path = self.hypr / "autostart.lua"
        hyprland_path.write_text(hyprland_path.read_text() + "\n  \n")
        autostart_path.write_text(autostart_path.read_text() + "\n\n")
        before_hyprland = hyprland_path.read_text()
        before_autostart = autostart_path.read_text()

        setup = self.run_script("setup.sh", "--yes")
        uninstall = self.run_script("uninstall.sh", "--yes")
        self.assertEqual(setup.returncode, 0, setup.stdout + setup.stderr)
        self.assertEqual(uninstall.returncode, 0, uninstall.stdout + uninstall.stderr)
        self.assertEqual((self.hypr / "hyprland.lua").read_text(), before_hyprland)
        self.assertEqual((self.hypr / "autostart.lua").read_text(), before_autostart)
        self.assertFalse((self.hypr / "classic-windows.lua").exists())

    def test_uninstall_removes_the_plugin_floating_mode_marker(self):
        setup = self.run_script("setup.sh", "--yes")
        self.assertEqual(setup.returncode, 0, setup.stdout + setup.stderr)
        marker = (
            self.home
            / ".local"
            / "state"
            / "omarchy-classic-windows"
            / "floating-mode.enabled"
        )
        marker.touch()

        uninstall = self.run_script("uninstall.sh", "--yes")

        self.assertEqual(uninstall.returncode, 0, uninstall.stdout + uninstall.stderr)
        self.assertFalse(marker.exists())

    def test_setup_fails_safely_when_not_running_omarchy_lua_config(self):
        (self.hypr / "hyprland.lua").unlink()
        result = self.run_script("setup.sh", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not find your Omarchy Hyprland configuration", result.stderr)
        self.assertFalse((self.hypr / "classic-windows.lua").exists())

    def test_setup_does_not_require_omarchy_path_environment_variable(self):
        self.env.pop("OMARCHY_PATH", None)

        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.hypr / "classic-windows.lua").exists())

    def test_empty_xdg_config_home_uses_default_config_loader(self):
        self.env["XDG_CONFIG_HOME"] = ""

        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.hypr / "classic-windows.lua").exists())
        self.assertIn(LOADER_LINE, (self.hypr / "hyprland.lua").read_text())

    def test_setup_honors_xdg_config_home_in_loader(self):
        xdg_hypr = self.base / "xdg-config" / "hypr"
        xdg_hypr.mkdir(parents=True)
        shutil.copy(FIXTURES / "hyprland.lua", xdg_hypr / "hyprland.lua")
        shutil.copy(FIXTURES / "autostart.lua", xdg_hypr / "autostart.lua")
        self.env["XDG_CONFIG_HOME"] = str(self.base / "xdg-config")

        result = self.run_script("setup.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((xdg_hypr / "classic-windows.lua").exists())
        loader = (xdg_hypr / "hyprland.lua").read_text()
        self.assertIn(LOADER_LINE, loader)
        self.assertNotIn('dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")', loader)

    def test_xdg_setup_migrates_and_uninstall_restores_legacy_loader(self):
        legacy = 'dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")'
        xdg_hypr = self.base / "xdg-config" / "hypr"
        xdg_hypr.mkdir(parents=True)
        shutil.copy(FIXTURES / "hyprland.lua", xdg_hypr / "hyprland.lua")
        shutil.copy(FIXTURES / "autostart.lua", xdg_hypr / "autostart.lua")
        hyprland_path = xdg_hypr / "hyprland.lua"
        hyprland_path.write_text(hyprland_path.read_text() + legacy + "\n")
        self.env["XDG_CONFIG_HOME"] = str(self.base / "xdg-config")

        setup = self.run_script("setup.sh", "--yes")
        after_setup = hyprland_path.read_text()
        uninstall = self.run_script("uninstall.sh", "--yes")
        after_uninstall = hyprland_path.read_text()

        self.assertEqual(setup.returncode, 0, setup.stdout + setup.stderr)
        self.assertEqual(uninstall.returncode, 0, uninstall.stdout + uninstall.stderr)
        self.assertNotIn(legacy, after_setup)
        self.assertEqual(after_setup.count(LOADER_LINE), 1)
        self.assertEqual(after_uninstall.count(legacy), 1)
        self.assertNotIn(LOADER_LINE, after_uninstall)

    def test_uninstall_preserves_a_user_modified_migrated_loader(self):
        legacy = 'dofile(os.getenv("HOME") .. "/.config/hypr/classic-windows.lua")'
        custom = '-- user replaced the Classic Windows loader'
        xdg_hypr = self.base / "xdg-config" / "hypr"
        xdg_hypr.mkdir(parents=True)
        shutil.copy(FIXTURES / "hyprland.lua", xdg_hypr / "hyprland.lua")
        shutil.copy(FIXTURES / "autostart.lua", xdg_hypr / "autostart.lua")
        hyprland_path = xdg_hypr / "hyprland.lua"
        hyprland_path.write_text(hyprland_path.read_text() + legacy + "\n")
        self.env["XDG_CONFIG_HOME"] = str(self.base / "xdg-config")

        setup = self.run_script("setup.sh", "--yes")
        self.assertEqual(setup.returncode, 0, setup.stdout + setup.stderr)
        hyprland_path.write_text(hyprland_path.read_text().replace(LOADER_LINE, custom))
        uninstall = self.run_script("uninstall.sh", "--yes")

        self.assertEqual(uninstall.returncode, 0, uninstall.stdout + uninstall.stderr)
        self.assertIn("Kept the changed loader", uninstall.stdout)
        self.assertIn(custom, hyprland_path.read_text())
        self.assertFalse((xdg_hypr / "classic-windows.lua").exists())

    def test_uninstall_without_install_preserves_unknown_state(self):
        state = self.home / ".local" / "state" / "omarchy-classic-windows"
        state.mkdir(parents=True)
        sentinel = state / "user.note"
        sentinel.write_text("keep me\n")
        before_hyprland = (self.hypr / "hyprland.lua").read_text()

        result = self.run_script("uninstall.sh", "--yes")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("not installed", result.stdout)
        self.assertEqual(sentinel.read_text(), "keep me\n")
        self.assertEqual((self.hypr / "hyprland.lua").read_text(), before_hyprland)


if __name__ == "__main__":
    unittest.main()
