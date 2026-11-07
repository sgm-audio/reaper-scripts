#!/usr/bin/env python3
"""Smoke tests for the actual importable modules in this checkout."""

import importlib
import importlib.util
import os
import sys
import tempfile
import traceback


ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def test_ai_integration():
    print("Testing AAF / REAPER integration module...")
    try:
        module = importlib.import_module("reaper_ai_integration")
        assert module.AAFInterface is not None
        assert module.ReaperInterface is not None
        assert module.UserInteraction is not None
        assert module.have_reaper is False, "Test process must not masquerade as REAPER"
        interface = module.AAFInterface()
        interface.close()  # Closing an unopened interface must be safe.
        print("  [OK] Public interfaces imported; standalone runtime detected")
        if module.aaf2 is None:
            print("  [INFO] pyaaf2 is optional and not installed")
        else:
            print("  [OK] pyaaf2 is installed")
        return True
    except Exception:
        traceback.print_exc()
        return False


def test_plugin_compatibility():
    print("\nTesting plugin compatibility system...")
    # Hyphens require a file-based import rather than normal module syntax.
    spec = importlib.util.spec_from_file_location(
        "plugin_compatibility_system",
        os.path.join(ROOT, "plugin-compatibility-system.py"),
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            db_path = os.path.join(temp_dir, "plugins.db")
            database = module.PluginDatabase(db_path)
            assert database.find_plugin("ReaEQ").plugin_id == "rea_eq"
            initial = database.get_alternatives("rea_eq")
            module.PluginDatabase(db_path)
            assert database.get_alternatives("rea_eq") == initial, (
                "Repeated initialization duplicated alternatives"
            )
            scanner = module.PluginScanner()
            assert isinstance(scanner.scan_plugins(), dict)
        print("  [OK] Database persistence, idempotence, and scanner")
        return True
    except Exception:
        traceback.print_exc()
        return False


def test_suno_configuration():
    print("\nTesting Suno configuration...")
    try:
        config_module = importlib.import_module("suno_workflow_config_system")
        first = config_module.WorkflowConfig()
        second = config_module.WorkflowConfig()
        assert first.paths.audio_extensions is not second.paths.audio_extensions
        first.paths.audio_extensions.append(".test")
        assert ".test" not in second.paths.audio_extensions
        relative = config_module.PathConfig(output_dir="relative-output")
        assert config_module.validate_config(
            config_module.WorkflowConfig(paths=relative)
        ) == []
        print("  [OK] Independent defaults and relative output paths")
        return True
    except Exception:
        traceback.print_exc()
        return False


def main():
    print("=" * 60)
    print("REAPER Scripts - Module Tests")
    print("=" * 60)
    tests = [
        ("AAF Integration", test_ai_integration),
        ("Plugin Compatibility", test_plugin_compatibility),
        ("Suno Configuration", test_suno_configuration),
    ]
    results = []
    for name, test in tests:
        try:
            result = test()
        except Exception:
            traceback.print_exc()
            result = False
        results.append((name, result))

    print("\n" + "=" * 60)
    for name, result in results:
        print(f"{name}: {'[PASSED]' if result else '[FAILED]'}")
    passed = sum(result for _, result in results)
    print(f"Total: {passed}/{len(results)} tests passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
