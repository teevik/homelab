import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("local_cache", Path(__file__).with_name("cache-local.py"))
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)


class LocalCacheTests(unittest.TestCase):
    def test_rejects_commands_and_caller_paths(self):
        cache = Mock()
        for operation in ["exec", "nix-store --serve --write", "prune", "sign", None]:
            with self.subTest(operation=operation), self.assertRaises(ValueError):
                local.handle(cache, {}, {"operation": operation, "directory": "/etc"}, Path("/unused"))
        self.assertEqual(cache.mock_calls, [])

    def test_failed_retention_preserves_pending_roots(self):
        with tempfile.TemporaryDirectory() as directory:
            pending = Path(directory)
            root = pending / ("0" * 32 + "-output")
            root.symlink_to("/nix/store/" + root.name)
            cache = Mock()
            cache.retain_dependencies.side_effect = ValueError("full")
            with self.assertRaises(ValueError):
                local.handle(cache, {}, {"operation": "flush"}, pending)
            self.assertTrue(root.is_symlink())
            cache.retain_dependencies.side_effect = None
            self.assertEqual(local.handle(cache, {}, {"operation": "flush"}, pending), {"retainedOutputs": 1})
            self.assertFalse(root.is_symlink())


if __name__ == "__main__":
    unittest.main()
