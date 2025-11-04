#!/usr/bin/env python3
"""
Update version pins in requirements files based on installed packages.

This script reads installed_packages.txt (from pip freeze) and updates
version pins in requirements files, preserving extras, comments, and git URLs.
"""

import re
import sys
from pathlib import Path


def parse_installed_packages(installed_file):
    """Parse installed_packages.txt into a dictionary of package -> version."""
    installed = {}
    with open(installed_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            # Handle lines like: package==version or package[extras]==version
            # or file:///path/to/package (skip these)
            if '==' in line and not line.startswith('file://'):
                # Extract package name and version
                # Handle both: package==version and package[extras]==version
                match = re.match(r'^([^=]+)==(.+)$', line)
                if match:
                    pkg_with_extras = match.group(1)
                    version = match.group(2)
                    # Extract base package name (remove extras)
                    base_pkg = re.match(r'^([^\[]+)', pkg_with_extras).group(1)
                    installed[base_pkg.lower()] = version
    
    return installed


def extract_package_name(line):
    """
    Extract base package name from a requirements line.
    Returns (package_name, has_version, extras) or None if not a package line.
    """
    line = line.strip()
    
    # Skip empty lines, comments, and git URLs
    if not line or line.startswith('#') or line.startswith('git+'):
        return None
    
    # Match patterns like:
    # package==version
    # package[extras]==version
    # package[extras]  (no version)
    # package (no version, no extras)
    
    # First, extract extras if present
    extras_match = re.match(r'^([^\[]+)\[([^\]]+)\](.*)$', line)
    if extras_match:
        base_pkg = extras_match.group(1)
        extras = extras_match.group(2)
        rest = extras_match.group(3)
        
        # Check if version is present
        if rest.startswith('=='):
            version = rest[2:].strip()
            return (base_pkg.lower(), True, f"[{extras}]", version)
        else:
            return (base_pkg.lower(), False, f"[{extras}]", None)
    
    # No extras, check for version
    if '==' in line:
        parts = line.split('==', 1)
        pkg = parts[0].strip()
        version = parts[1].strip()
        return (pkg.lower(), True, "", version)
    else:
        # No version specified
        pkg = line.strip()
        return (pkg.lower(), False, "", None)


def update_requirements_file(req_file, installed_packages):
    """Update version pins in a requirements file."""
    lines = []
    updated_count = 0
    not_found = []
    
    with open(req_file, 'r') as f:
        for line in f:
            original_line = line
            line = line.rstrip('\n')
            
            pkg_info = extract_package_name(line)
            
            if pkg_info is None:
                # Comment, git URL, or empty line - keep as is
                lines.append(original_line.rstrip('\n'))
                continue
            
            pkg_name, has_version, extras, old_version = pkg_info
            
            # Look up installed version
            if pkg_name in installed_packages:
                new_version = installed_packages[pkg_name]
                
                # Update the line
                if has_version:
                    # Replace existing version
                    new_line = re.sub(
                        r'==[^\s#]+',
                        f'=={new_version}',
                        line,
                        count=1
                    )
                    if old_version != new_version:
                        updated_count += 1
                else:
                    # Add version
                    new_line = f"{line.rstrip()}=={new_version}"
                    updated_count += 1
                
                lines.append(new_line)
            else:
                # Package not found in installed packages - keep original
                lines.append(line)
                if pkg_name not in ['jax', 'jaxlib']:  # Skip known special cases
                    not_found.append(pkg_name)
    
    return lines, updated_count, not_found


def main():
    if len(sys.argv) < 3:
        print("Usage: update_requirements_versions.py <installed_packages.txt> <req_file1> [req_file2] ...")
        print("\nExample:")
        print("  update_requirements_versions.py installed_packages.txt requirements/common.txt requirements/jax_common.txt")
        sys.exit(1)
    
    installed_file = Path(sys.argv[1])
    req_files = [Path(f) for f in sys.argv[2:]]
    
    if not installed_file.exists():
        print(f"Error: {installed_file} not found")
        sys.exit(1)
    
    # Parse installed packages
    print(f"Reading installed packages from {installed_file}...")
    installed_packages = parse_installed_packages(installed_file)
    print(f"Found {len(installed_packages)} installed packages\n")
    
    # Update each requirements file
    for req_file in req_files:
        if not req_file.exists():
            print(f"Warning: {req_file} not found, skipping")
            continue
        
        print(f"Updating {req_file}...")
        lines, updated_count, not_found = update_requirements_file(req_file, installed_packages)
        
        # Write updated file
        with open(req_file, 'w') as f:
            for line in lines:
                f.write(line + '\n')
        
        print(f"  Updated {updated_count} package versions")
        if not_found:
            print(f"  Warning: {len(not_found)} packages not found in installed packages: {', '.join(not_found[:5])}")
            if len(not_found) > 5:
                print(f"  ... and {len(not_found) - 5} more")
        print()


if __name__ == '__main__':
    main()

