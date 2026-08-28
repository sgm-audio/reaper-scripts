#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for REAPER Template System
Verifies all modules are functional
"""

import sys
import os

def test_ai_integration():
    """Test AI integration module"""
    print("Testing AI Integration Module...")
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'files'))

        # Import with hyphen in filename
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "ai_integration_module",
            os.path.join(os.path.dirname(__file__), 'files', 'ai-integration-module.py')
        )
        ai_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ai_module)

        import numpy as np

        # Test basic initialization
        ai_system = ai_module.AIProductionSystem()
        print("  [OK] AIProductionSystem initialized")

        # Test audio analysis
        test_project = {
            'tracks': [],
            'master_bus_audio': np.random.randn(48000, 2) * 0.1,
            'sample_rate': 48000
        }

        result = ai_module.analyze_project(test_project)
        print("  [OK] Project analysis completed")
        print(f"  [OK] Analysis keys: {list(result.keys())}")

        return True
    except Exception as e:
        print(f"  [FAIL] Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_plugin_compatibility():
    """Test plugin compatibility system"""
    print("\nTesting Plugin Compatibility System...")
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'files'))

        # Import with hyphen in filename
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "plugin_compatibility_system",
            os.path.join(os.path.dirname(__file__), 'files', 'plugin-compatibility-system.py')
        )
        plugin_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(plugin_module)

        # Test database initialization
        db = plugin_module.PluginDatabase("test_plugin.db")
        print("  [OK] Plugin database initialized")

        # Test plugin scanner
        scanner = plugin_module.PluginScanner()
        print("  [OK] Plugin scanner initialized")
        print(f"  [OK] Scan paths: {len(scanner.plugin_paths)} paths")

        # Cleanup
        if os.path.exists("test_plugin.db"):
            os.remove("test_plugin.db")

        return True
    except Exception as e:
        print(f"  [FAIL] Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_template_validator():
    """Test template validator"""
    print("\nTesting Template Validator...")
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'files'))

        # Import with hyphen in filename
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "template_validator",
            os.path.join(os.path.dirname(__file__), 'files', 'template-validator.py')
        )
        template_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(template_module)

        # Test validator initialization
        validator = template_module.TemplateValidator(os.path.dirname(__file__))
        print("  [OK] Template validator initialized")

        return True
    except Exception as e:
        print(f"  [FAIL] Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Run all tests"""
    print("=" * 60)
    print("REAPER Template System - Module Tests")
    print("=" * 60)

    results = []

    # Run tests
    results.append(("AI Integration", test_ai_integration()))
    results.append(("Plugin Compatibility", test_plugin_compatibility()))
    results.append(("Template Validator", test_template_validator()))

    # Print summary
    print("\n" + "=" * 60)
    print("Test Summary:")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = "[PASSED]" if result else "[FAILED]"
        print(f"{name}: {status}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n[SUCCESS] All modules are functional!")
        return 0
    else:
        print(f"\n[FAILURE] {total - passed} module(s) failed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
