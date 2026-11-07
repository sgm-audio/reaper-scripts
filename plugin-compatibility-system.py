# REAPER Plugin Compatibility System v3.0
# Comprehensive plugin database and compatibility checker
# Author: Scott Mills Audio Systems

import json
import os
import platform
import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import sqlite3
from datetime import datetime
from pathlib import Path

class PluginFormat(Enum):
    VST2 = "VST"
    VST3 = "VST3" 
    AU = "AudioUnit"
    AAX = "AAX"
    CLAP = "CLAP"
    LV2 = "LV2"
    JS = "JS"

class PluginCategory(Enum):
    EQ = "Equalizer"
    COMPRESSOR = "Compressor"
    REVERB = "Reverb"
    DELAY = "Delay"
    MODULATION = "Modulation"
    DISTORTION = "Distortion"
    SYNTHESIZER = "Synthesizer"
    SAMPLER = "Sampler"
    UTILITY = "Utility"
    ANALYZER = "Analyzer"
    MASTERING = "Mastering"

@dataclass
class PluginInfo:
    """Complete plugin information"""
    plugin_id: str
    name: str
    manufacturer: str
    version: str
    format: PluginFormat
    category: PluginCategory
    
    # Compatibility
    windows_compatible: bool
    mac_compatible: bool
    linux_compatible: bool
    
    # Requirements
    min_reaper_version: str
    requires_license: bool
    is_free: bool
    
    # Performance
    cpu_usage: str  # low, medium, high
    latency: int  # samples
    supports_oversampling: bool
    
    # Features
    preset_count: int
    midi_learn: bool
    automation_parameters: int
    
    # Alternatives
    alternatives: List[str]
    
    # Metadata
    website: str
    last_updated: datetime
    notes: str

class PluginDatabase:
    """Central plugin compatibility database"""
    
    def __init__(self, db_path: str = "plugin_compatibility.db"):
        self.db_path = db_path
        self._init_database()
        self._populate_core_plugins()
    
    def _init_database(self):
        """Initialize SQLite database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create main plugin table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS plugins (
                plugin_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                manufacturer TEXT,
                version TEXT,
                format TEXT,
                category TEXT,
                windows_compatible INTEGER,
                mac_compatible INTEGER,
                linux_compatible INTEGER,
                min_reaper_version TEXT,
                requires_license INTEGER,
                is_free INTEGER,
                cpu_usage TEXT,
                latency INTEGER,
                supports_oversampling INTEGER,
                preset_count INTEGER,
                midi_learn INTEGER,
                automation_parameters INTEGER,
                website TEXT,
                last_updated TIMESTAMP,
                notes TEXT
            )
        ''')
        
        # Create alternatives table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS plugin_alternatives (
                plugin_id TEXT,
                alternative_id TEXT,
                quality_match REAL,
                notes TEXT,
                FOREIGN KEY (plugin_id) REFERENCES plugins(plugin_id),
                FOREIGN KEY (alternative_id) REFERENCES plugins(plugin_id),
                UNIQUE(plugin_id, alternative_id)
            )
        ''')
        
        # Create presets table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS plugin_presets (
                preset_id TEXT PRIMARY KEY,
                plugin_id TEXT,
                preset_name TEXT,
                category TEXT,
                data BLOB,
                FOREIGN KEY (plugin_id) REFERENCES plugins(plugin_id)
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def _populate_core_plugins(self):
        """Populate database with core plugin information"""
        core_plugins = [
            # REAPER Built-in Plugins
            PluginInfo(
                plugin_id="rea_eq",
                name="ReaEQ",
                manufacturer="Cockos",
                version="*",
                format=PluginFormat.VST2,
                category=PluginCategory.EQ,
                windows_compatible=True,
                mac_compatible=True,
                linux_compatible=True,
                min_reaper_version="5.0",
                requires_license=False,
                is_free=True,
                cpu_usage="low",
                latency=0,
                supports_oversampling=False,
                preset_count=0,
                midi_learn=True,
                automation_parameters=999,
                alternatives=["fabfilter_proq3", "waves_req", "dmg_equilibrium"],
                website="https://reaper.fm",
                last_updated=datetime.now(),
                notes="Built-in REAPER EQ, highly efficient"
            ),
            
            # Popular Third-Party Plugins
            PluginInfo(
                plugin_id="fabfilter_proq3",
                name="Pro-Q 3",
                manufacturer="FabFilter",
                version="3.x",
                format=PluginFormat.VST3,
                category=PluginCategory.EQ,
                windows_compatible=True,
                mac_compatible=True,
                linux_compatible=False,
                min_reaper_version="5.0",
                requires_license=True,
                is_free=False,
                cpu_usage="medium",
                latency=0,
                supports_oversampling=True,
                preset_count=200,
                midi_learn=True,
                automation_parameters=999,
                alternatives=["rea_eq", "tdr_nova", "melda_mequalizer"],
                website="https://www.fabfilter.com",
                last_updated=datetime.now(),
                notes="Industry standard EQ with dynamic bands"
            ),
            
            PluginInfo(
                plugin_id="waves_ssl_comp",
                name="SSL G-Master Buss Compressor",
                manufacturer="Waves",
                version="11+",
                format=PluginFormat.VST3,
                category=PluginCategory.COMPRESSOR,
                windows_compatible=True,
                mac_compatible=True,
                linux_compatible=False,
                min_reaper_version="5.0",
                requires_license=True,
                is_free=False,
                cpu_usage="low",
                latency=0,
                supports_oversampling=False,
                preset_count=50,
                midi_learn=False,
                automation_parameters=6,
                alternatives=["rea_comp", "tdr_kotelnikov", "cytomic_glue"],
                website="https://www.waves.com",
                last_updated=datetime.now(),
                notes="Classic SSL bus compressor emulation"
            )
        ]
        
        # Add to database
        for plugin in core_plugins:
            self.add_plugin(plugin)
    
    def add_plugin(self, plugin: PluginInfo) -> bool:
        """Add or update plugin in database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        try:
            cursor.execute('''
                INSERT OR REPLACE INTO plugins VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
            ''', (
                plugin.plugin_id,
                plugin.name,
                plugin.manufacturer,
                plugin.version,
                plugin.format.value,
                plugin.category.value,
                int(plugin.windows_compatible),
                int(plugin.mac_compatible),
                int(plugin.linux_compatible),
                plugin.min_reaper_version,
                int(plugin.requires_license),
                int(plugin.is_free),
                plugin.cpu_usage,
                plugin.latency,
                int(plugin.supports_oversampling),
                plugin.preset_count,
                int(plugin.midi_learn),
                plugin.automation_parameters,
                plugin.website,
                plugin.last_updated,
                plugin.notes
            ))
            
            # Replace the relationship set atomically; repeated initialization
            # must not accumulate duplicate alternatives in older databases.
            cursor.execute(
                "DELETE FROM plugin_alternatives WHERE plugin_id = ?",
                (plugin.plugin_id,),
            )
            for alt in plugin.alternatives:
                cursor.execute('''
                    INSERT OR IGNORE INTO plugin_alternatives
                    VALUES (?, ?, ?, ?)
                ''', (plugin.plugin_id, alt, 0.8, ""))
            
            conn.commit()
            return True
            
        except Exception as e:
            print(f"Error adding plugin: {e}")
            return False
        finally:
            conn.close()
    
    def find_plugin(self, plugin_name: str) -> Optional[PluginInfo]:
        """Find plugin by name or ID"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Try exact match first
        cursor.execute('''
            SELECT * FROM plugins 
            WHERE plugin_id = ? OR name = ?
        ''', (plugin_name, plugin_name))
        
        result = cursor.fetchone()
        
        if not result:
            # Try fuzzy match
            cursor.execute('''
                SELECT * FROM plugins 
                WHERE name LIKE ? OR plugin_id LIKE ?
            ''', (f'%{plugin_name}%', f'%{plugin_name}%'))
            result = cursor.fetchone()
        
        conn.close()
        
        if result:
            return self._row_to_plugin_info(result)
        return None
    
    def get_alternatives(self, plugin_id: str) -> List[Tuple[str, float]]:
        """Get alternative plugins with quality match score"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT alternative_id, quality_match 
            FROM plugin_alternatives 
            WHERE plugin_id = ?
            ORDER BY quality_match DESC
        ''', (plugin_id,))
        
        alternatives = cursor.fetchall()
        conn.close()
        
        return alternatives
    
    def _row_to_plugin_info(self, row) -> PluginInfo:
        """Convert database row to PluginInfo object"""
        return PluginInfo(
            plugin_id=row[0],
            name=row[1],
            manufacturer=row[2],
            version=row[3],
            format=PluginFormat(row[4]),
            category=PluginCategory(row[5]),
            windows_compatible=bool(row[6]),
            mac_compatible=bool(row[7]),
            linux_compatible=bool(row[8]),
            min_reaper_version=row[9],
            requires_license=bool(row[10]),
            is_free=bool(row[11]),
            cpu_usage=row[12],
            latency=row[13],
            supports_oversampling=bool(row[14]),
            preset_count=row[15],
            midi_learn=bool(row[16]),
            automation_parameters=row[17],
            alternatives=[],  # Loaded separately
            website=row[18],
            last_updated=(
                row[19]
                if isinstance(row[19], datetime)
                else datetime.fromisoformat(row[19])
            ),
            notes=row[20]
        )

    def export_json(self, output_path: str):
        """Export plugin metadata and alternative relationships to JSON."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            plugins = [dict(row) for row in conn.execute("SELECT * FROM plugins")]
            alternatives = [
                dict(row) for row in conn.execute("SELECT * FROM plugin_alternatives")
            ]
        with open(output_path, "w", encoding="utf-8") as output:
            json.dump(
                {"plugins": plugins, "alternatives": alternatives},
                output,
                indent=2,
                default=str,
            )

    def import_json(self, input_path: str):
        """Import data produced by :meth:`export_json`."""
        with open(input_path, "r", encoding="utf-8") as source:
            data = json.load(source)
        if not isinstance(data, dict) or not isinstance(data.get("plugins"), list):
            raise ValueError("Invalid plugin database export")
        alternatives = {}
        for relationship in data.get("alternatives", []):
            alternatives.setdefault(relationship["plugin_id"], []).append(
                relationship["alternative_id"]
            )
        for row in data["plugins"]:
            plugin = PluginInfo(
                plugin_id=row["plugin_id"],
                name=row["name"],
                manufacturer=row.get("manufacturer", ""),
                version=row.get("version", ""),
                format=PluginFormat(row["format"]),
                category=PluginCategory(row["category"]),
                windows_compatible=bool(row.get("windows_compatible", True)),
                mac_compatible=bool(row.get("mac_compatible", True)),
                linux_compatible=bool(row.get("linux_compatible", True)),
                min_reaper_version=row.get("min_reaper_version", ""),
                requires_license=bool(row.get("requires_license", True)),
                is_free=bool(row.get("is_free", False)),
                cpu_usage=row.get("cpu_usage", "unknown"),
                latency=int(row.get("latency", 0)),
                supports_oversampling=bool(row.get("supports_oversampling", False)),
                preset_count=int(row.get("preset_count", 0)),
                midi_learn=bool(row.get("midi_learn", False)),
                automation_parameters=int(row.get("automation_parameters", 0)),
                alternatives=alternatives.get(row["plugin_id"], []),
                website=row.get("website", ""),
                last_updated=datetime.fromisoformat(row["last_updated"]),
                notes=row.get("notes", ""),
            )
            self.add_plugin(plugin)

class PluginScanner:
    """Scan system for installed plugins"""
    
    def __init__(self):
        self.system = platform.system()
        self.plugin_paths = self._get_plugin_paths()
        self.installed_plugins = {}
    
    def _get_plugin_paths(self) -> List[str]:
        """Get standard plugin paths for current OS"""
        paths = []
        
        if self.system == "Windows":
            paths = [
                "C:\\Program Files\\VSTPlugins",
                "C:\\Program Files\\Steinberg\\VSTPlugins",
                "C:\\Program Files\\Common Files\\VST3",
                "C:\\Program Files (x86)\\VSTPlugins",
                "C:\\Program Files (x86)\\Steinberg\\VSTPlugins"
            ]
        elif self.system == "Darwin":  # macOS
            home = os.path.expanduser("~")
            paths = [
                "/Library/Audio/Plug-Ins/VST",
                "/Library/Audio/Plug-Ins/VST3",
                "/Library/Audio/Plug-Ins/Components",
                f"{home}/Library/Audio/Plug-Ins/VST",
                f"{home}/Library/Audio/Plug-Ins/VST3",
                f"{home}/Library/Audio/Plug-Ins/Components"
            ]
        elif self.system == "Linux":
            home = os.path.expanduser("~")
            paths = [
                "/usr/lib/vst",
                "/usr/lib/vst3",
                "/usr/local/lib/vst",
                "/usr/local/lib/vst3",
                f"{home}/.vst",
                f"{home}/.vst3"
            ]
        
        # Add installation and per-user REAPER resource paths.
        reaper_path = self._find_reaper_path()
        if reaper_path:
            paths.append(os.path.join(reaper_path, "Plugins"))
            paths.append(os.path.join(reaper_path, "Effects"))
        if self.system == "Windows" and os.getenv("APPDATA"):
            paths.append(os.path.join(os.environ["APPDATA"], "REAPER", "Effects"))
        elif self.system == "Darwin":
            paths.append(os.path.expanduser("~/Library/Application Support/REAPER/Effects"))
        elif self.system == "Linux":
            paths.append(os.path.expanduser("~/.config/REAPER/Effects"))

        return sorted({p for p in paths if os.path.isdir(p)})
    
    def _find_reaper_path(self) -> Optional[str]:
        """Find REAPER installation path"""
        if self.system == "Windows":
            paths = [
                "C:\\Program Files\\REAPER",
                "C:\\Program Files (x86)\\REAPER"
            ]
        elif self.system == "Darwin":
            paths = ["/Applications/REAPER.app/Contents/Resources"]
        else:
            paths = [
                "/opt/REAPER",
                os.path.expanduser("~/.config/REAPER"),
            ]
        
        for path in paths:
            if os.path.exists(path):
                return path
        return None
    
    def scan_plugins(self) -> Dict[str, List[str]]:
        """Scan files and plugin bundles without descending into bundle contents."""
        plugins = {
            'vst2': [], 'vst3': [], 'au': [], 'js': [], 'clap': [], 'lv2': []
        }
        bundle_formats = {
            '.vst': 'vst2', '.vst3': 'vst3', '.component': 'au', '.lv2': 'lv2'
        }
        file_formats = {
            '.dll': 'vst2', '.vst': 'vst2', '.so': 'vst2',
            '.vst3': 'vst3', '.component': 'au', '.clap': 'clap',
            '.js': 'js', '.jsfx': 'js', '.lv2': 'lv2'
        }

        for path in self.plugin_paths:
            if not os.path.isdir(path):
                continue
            for root, dirs, files in os.walk(path):
                # VST3/AU/LV2 (and VST2 on macOS) are directories, not files.
                for dirname in list(dirs):
                    format_name = bundle_formats.get(os.path.splitext(dirname)[1].lower())
                    if format_name:
                        plugins[format_name].append(os.path.join(root, dirname))
                        dirs.remove(dirname)
                for filename in files:
                    extension = os.path.splitext(filename)[1].lower()
                    format_name = file_formats.get(extension)
                    if format_name:
                        plugins[format_name].append(os.path.join(root, filename))
                    elif (not extension and 'Effects' in Path(path).parts
                          and not filename.endswith('.jsfx-inc')):
                        # Native JSFX files commonly have no extension.
                        plugins['js'].append(os.path.join(root, filename))

        for format_name, paths in plugins.items():
            plugins[format_name] = sorted(set(paths))
        self.installed_plugins = plugins
        return plugins
    
    def get_plugin_info(self, plugin_path: str) -> Optional[Dict]:
        """Extract plugin information from file"""
        info = {
            'path': plugin_path,
            'filename': os.path.basename(plugin_path),
            'size': os.path.getsize(plugin_path),
            'modified': datetime.fromtimestamp(os.path.getmtime(plugin_path))
        }
        
        # Try to extract more info based on file type
        if plugin_path.endswith('.vst3'):
            info['format'] = 'VST3'
            # VST3 packages often have metadata we can read
            metadata_path = os.path.join(plugin_path, 'Contents', 'Info.plist')
            if os.path.exists(metadata_path):
                try:
                    import plistlib
                    with open(metadata_path, 'rb') as f:
                        plist = plistlib.load(f)
                        info['bundle_name'] = plist.get('CFBundleName', '')
                        info['version'] = plist.get('CFBundleVersion', '')
                        info['manufacturer'] = plist.get('CFBundleGetInfoString', '')
                except:
                    pass
        
        return info

class CompatibilityChecker:
    """Check plugin compatibility for templates"""
    
    def __init__(self):
        self.db = PluginDatabase()
        self.scanner = PluginScanner()
        self.compatibility_report = {}

    @staticmethod
    def _normalize_plugin_name(name: str) -> str:
        """Normalize RPP descriptors and filenames for conservative matching."""
        normalized = os.path.basename(name).strip()
        normalized = re.sub(
            r"^(?:VST3?|VSTi|AU|CLAP|JS):\s*", "", normalized, flags=re.IGNORECASE
        )
        normalized = os.path.splitext(normalized)[0]
        # RPP display names commonly end with the vendor in parentheses.
        normalized = re.sub(r"\s*\([^()]*\)\s*$", "", normalized)
        return re.sub(r"[^a-z0-9]+", "", normalized.lower())

    def _is_installed(self, plugin_name: str, installed_names: List[str]) -> bool:
        target = self._normalize_plugin_name(plugin_name)
        return bool(target) and any(
            self._normalize_plugin_name(installed) == target
            for installed in installed_names
        )

    def check_template_compatibility(self, template_path: str) -> Dict:
        """Check all plugins in a template for compatibility"""
        report = {
            'template': template_path,
            'total_plugins': 0,
            'missing_plugins': [],
            'incompatible_plugins': [],
            'alternatives_available': {},
            'warnings': [],
            'errors': [],
            'score': 100.0
        }
        if not os.path.isfile(template_path):
            report['errors'].append(f'Template not found: {template_path}')
            report['score'] = 0.0
            self.compatibility_report = report
            return report

        # Parse template file
        plugins_used = self._parse_template_plugins(template_path)
        report['total_plugins'] = len(plugins_used)
        
        # Scan installed plugins
        installed = self.scanner.scan_plugins()
        installed_names = self._extract_plugin_names(installed)
        
        # Check each plugin
        for plugin_name in plugins_used:
            plugin_info = self.db.find_plugin(plugin_name)
            is_installed = self._is_installed(plugin_name, installed_names) or (
                plugin_info is not None
                and self._is_installed(plugin_info.name, installed_names)
            )

            if plugin_info:
                # Check OS compatibility
                if not self._is_compatible_with_os(plugin_info):
                    report['incompatible_plugins'].append({
                        'name': plugin_name,
                        'reason': f'Not compatible with {platform.system()}'
                    })
                    report['score'] -= 10
                
                # Check if installed
                if not is_installed:
                    report['missing_plugins'].append(plugin_name)
                    report['score'] -= 5
                    
                    # Find alternatives
                    alternatives = self.db.get_alternatives(plugin_info.plugin_id)
                    if alternatives:
                        report['alternatives_available'][plugin_name] = [
                            {'name': alt[0], 'match': alt[1]} 
                            for alt in alternatives
                        ]
                
                # Check license requirements
                if plugin_info.requires_license:
                    report['warnings'].append(
                        f'{plugin_name} requires a valid license'
                    )
            else:
                report['warnings'].append(
                    f'{plugin_name} not found in database; compatibility unverified'
                )
                if not is_installed:
                    report['missing_plugins'].append(plugin_name)
                    report['score'] -= 5
        
        report['score'] = max(0, report['score'])
        self.compatibility_report = report
        return report
    
    def _parse_template_plugins(self, template_path: str) -> List[str]:
        """Extract plugin names from REAPER template"""
        plugins = []
        
        try:
            with open(template_path, 'r', encoding='utf-8') as f:
                content = f.read()
            descriptors = re.findall(
                r'<(?:VST|JS|AU|CLAP)\s+\"([^\"]+)\"', content,
                flags=re.IGNORECASE,
            )
            for descriptor in descriptors:
                name = re.sub(
                    r"^(?:VST3?|VSTi|AU|CLAP|JS):\s*", "", descriptor,
                    flags=re.IGNORECASE,
                ).strip()
                name = re.sub(r"\s*\([^()]*\)\s*$", "", name).strip()
                if name:
                    plugins.append(name)
        except (OSError, UnicodeError) as e:
            print(f"Error parsing template: {e}")

        return sorted(set(plugins))  # Remove duplicates

    def _extract_plugin_names(self, installed_plugins: Dict) -> List[str]:
        """Extract plugin names from installed paths"""
        names = []
        
        for format_type, paths in installed_plugins.items():
            for path in paths:
                # Extract name from filename
                filename = os.path.basename(path)
                name = os.path.splitext(filename)[0]
                names.append(name)
        
        return names
    
    def _is_compatible_with_os(self, plugin: PluginInfo) -> bool:
        """Check if plugin is compatible with current OS"""
        system = platform.system()
        
        if system == "Windows":
            return plugin.windows_compatible
        elif system == "Darwin":
            return plugin.mac_compatible
        elif system == "Linux":
            return plugin.linux_compatible
        
        return False
    
    def generate_compatibility_report(self) -> str:
        """Generate human-readable compatibility report"""
        if not self.compatibility_report:
            return "No compatibility check has been run."
        
        report = self.compatibility_report
        lines = []
        
        lines.append("=" * 60)
        lines.append("PLUGIN COMPATIBILITY REPORT")
        lines.append("=" * 60)
        lines.append(f"Template: {report['template']}")
        lines.append(f"Total Plugins: {report['total_plugins']}")
        lines.append(f"Compatibility Score: {report['score']:.1f}%")
        lines.append("")

        if report.get('errors'):
            lines.append("ERRORS:")
            for error in report['errors']:
                lines.append(f"  ✗ {error}")
            lines.append("")

        if report['missing_plugins']:
            lines.append("MISSING PLUGINS:")
            for plugin in report['missing_plugins']:
                lines.append(f"  ✗ {plugin}")
                if plugin in report['alternatives_available']:
                    lines.append("    Alternatives:")
                    for alt in report['alternatives_available'][plugin]:
                        lines.append(f"      - {alt['name']} ({alt['match']*100:.0f}% match)")
            lines.append("")
        
        if report['incompatible_plugins']:
            lines.append("INCOMPATIBLE PLUGINS:")
            for plugin in report['incompatible_plugins']:
                lines.append(f"  ✗ {plugin['name']}: {plugin['reason']}")
            lines.append("")
        
        if report['warnings']:
            lines.append("WARNINGS:")
            for warning in report['warnings']:
                lines.append(f"  ⚠ {warning}")
        
        return "\n".join(lines)
    
    def suggest_replacements(self) -> Dict[str, str]:
        """Suggest best replacement for each missing plugin"""
        replacements = {}
        
        for plugin in self.compatibility_report.get('missing_plugins', []):
            if plugin in self.compatibility_report.get('alternatives_available', {}):
                alternatives = self.compatibility_report['alternatives_available'][plugin]
                if alternatives:
                    # Get best alternative (highest match score)
                    best = max(alternatives, key=lambda x: x['match'])
                    replacements[plugin] = best['name']
        
        return replacements

class PluginPresetManager:
    """Manage and convert plugin presets"""
    
    def __init__(self, db: PluginDatabase):
        self.db = db
    
    def export_preset(self, plugin_id: str, preset_name: str) -> Optional[bytes]:
        """Export plugin preset data"""
        conn = sqlite3.connect(self.db.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT data FROM plugin_presets 
            WHERE plugin_id = ? AND preset_name = ?
        ''', (plugin_id, preset_name))
        
        result = cursor.fetchone()
        conn.close()
        
        return result[0] if result else None
    
    def convert_preset(self, 
                      source_plugin: str, 
                      target_plugin: str, 
                      preset_data: bytes) -> Optional[bytes]:
        """Convert preset between compatible plugins"""
        # This would implement preset conversion logic
        # For now, return None if plugins are incompatible
        
        source_info = self.db.find_plugin(source_plugin)
        target_info = self.db.find_plugin(target_plugin)
        
        if not source_info or not target_info:
            return None
        
        # Check if plugins are in same category
        if source_info.category != target_info.category:
            return None
        
        # Preset bytes are plugin-specific. Returning them unchanged would
        # falsely claim a conversion and could corrupt the target preset.
        return None

# Command-line interface
def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='REAPER Plugin Compatibility Checker')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Check command
    check_parser = subparsers.add_parser('check', help='Check template compatibility')
    check_parser.add_argument('template', help='Path to REAPER template')
    check_parser.add_argument('--suggest', action='store_true', 
                            help='Suggest replacements')
    
    # Scan command
    scan_parser = subparsers.add_parser('scan', help='Scan for installed plugins')
    scan_parser.add_argument('--save', help='Save scan results to file')
    
    # Database command
    db_parser = subparsers.add_parser('db', help='Database operations')
    db_parser.add_argument('--export', help='Export database to JSON')
    db_parser.add_argument('--import', dest='import_file', help='Import from JSON')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 0

    if args.command == 'check':
        checker = CompatibilityChecker()
        report = checker.check_template_compatibility(args.template)

        print(checker.generate_compatibility_report())
        
        if args.suggest:
            print("\nSUGGESTED REPLACEMENTS:")
            replacements = checker.suggest_replacements()
            for original, replacement in replacements.items():
                print(f"  {original} → {replacement}")
        return 1 if report.get('errors') else 0

    elif args.command == 'scan':
        scanner = PluginScanner()
        plugins = scanner.scan_plugins()
        
        print(f"Found {sum(len(p) for p in plugins.values())} plugins:")
        for format_type, plugin_list in plugins.items():
            if plugin_list:
                print(f"\n{format_type.upper()}: {len(plugin_list)} plugins")
                for plugin in plugin_list[:5]:  # Show first 5
                    print(f"  - {os.path.basename(plugin)}")
                if len(plugin_list) > 5:
                    print(f"  ... and {len(plugin_list) - 5} more")
        
        if args.save:
            with open(args.save, 'w') as f:
                json.dump(plugins, f, indent=2)
            print(f"\nScan results saved to {args.save}")
    
    elif args.command == 'db':
        database = PluginDatabase()
        if args.export:
            database.export_json(args.export)
            print(f"Database exported to {args.export}")
        elif args.import_file:
            database.import_json(args.import_file)
            print(f"Database imported from {args.import_file}")
        else:
            db_parser.print_help()

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
