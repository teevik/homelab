"""Publication boundaries and retention, without modifying a real store."""

import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("cache", Path(__file__).with_name("nix-cache-command.py"))
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


def system(number):
    return f"/nix/store/{number:032d}-nixos-system-desktop-test"


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = {
            "nix": "nix", "nixStore": "nix-store", "rootsDirectory": str(self.root),
            "storeDirectory": str(self.root), "hosts": ["desktop", "zenbook"],
            "minFreeBytes": 0, "budgetBytes": 1000, "keepGenerations": 2,
        }
        self.valid = {system(n) for n in range(1, 5)}
        self.register = patch.object(cache, "run", side_effect=self.realise).start()
        patch.object(cache, "path_info", side_effect=self.info).start()
        self.addCleanup(patch.stopall)

    def realise(self, *args):
        self.assertEqual(args[0:2], ("nix-store", "--realise"))
        self.assertEqual(args[-6:], ("--option", "substitute", "false", "--option", "max-jobs", "0"))
        if args[2] not in self.valid:
            raise ValueError("missing path")
        Path(args[4]).symlink_to(args[2])
        return args[2]

    def info(self, config, paths):
        result = {"/nix/store/" + "a" * 32 + "-shared-library": {"narSize": 10}}
        for path in paths:
            path = os.readlink(path) if Path(path).is_symlink() else path
            if path not in self.valid:
                raise ValueError("missing dependency")
            result[path] = {"narSize": 100}
        return result

    def test_retains_whole_generations_and_deduplicates_accounting(self):
        for n in range(1, 4):
            receipt = cache.publish(self.config, "desktop", str(n), system(n))
        self.assertFalse((self.root / "desktop/1").exists())
        self.assertTrue((self.root / "desktop/2").is_symlink())
        self.assertTrue((self.root / "desktop/3").is_symlink())
        self.assertEqual(os.readlink(self.root / "desktop/latest"), system(3))
        self.assertEqual(receipt["closurePaths"], 2)
        self.assertEqual(receipt["retainedBytes"], 210)

    def test_failed_verification_keeps_previous_latest(self):
        cache.publish(self.config, "desktop", "1", system(1))
        with patch.object(cache, "path_info", side_effect=ValueError("missing dependency")):
            with self.assertRaises(ValueError):
                cache.publish(self.config, "desktop", "2", system(2))
        self.assertEqual(os.readlink(self.root / "desktop/latest"), system(1))
        self.assertFalse((self.root / "desktop/2").is_symlink())

    def test_generation_cannot_be_reassigned(self):
        cache.publish(self.config, "desktop", "1", system(1))
        with self.assertRaises(ValueError):
            cache.publish(self.config, "desktop", "1", system(2))
        self.assertEqual(os.readlink(self.root / "desktop/latest"), system(1))

    def test_missing_path_never_replaces_latest(self):
        cache.publish(self.config, "desktop", "1", system(1))
        with self.assertRaises(ValueError):
            cache.publish(self.config, "desktop", "2", system(9))
        self.assertEqual(os.readlink(self.root / "desktop/latest"), system(1))

    def test_commands_and_paths_are_allowlisted(self):
        for command in [
            "", "bash", "nix-daemon --stdio", "nix-store --serve --write; id",
            "nix-store --serve --write --option require-sigs false", "cache-preflight -1",
            f"cache-publish laptop 1 {system(1)}", f"cache-publish desktop ../escape {system(1)}",
            f"cache-publish desktop latest {system(1)}", "cache-publish desktop 1 /etc/passwd",
        ]:
            with self.subTest(command=command), self.assertRaises(ValueError):
                cache.dispatch(self.config, command)
        self.register.assert_not_called()

    def test_headroom_is_checked_before_import(self):
        self.config["minFreeBytes"] = 100
        with patch.object(cache.os, "statvfs", return_value=SimpleNamespace(f_bavail=150, f_frsize=1)):
            with self.assertRaises(ValueError):
                cache.dispatch(self.config, "cache-preflight 51")
            self.assertEqual(cache.dispatch(self.config, "cache-preflight 50"), {"availableBytes": 150})


if __name__ == "__main__":
    unittest.main()
