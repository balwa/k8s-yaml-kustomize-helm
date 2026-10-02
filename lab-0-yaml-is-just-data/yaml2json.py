#!/usr/bin/env python3
"""Print a YAML file as JSON, one JSON document per YAML document.

Usage:  ./yaml2json.py file.yaml
        cat file.yaml | ./yaml2json.py
"""
import json
import sys

import yaml

src = open(sys.argv[1]) if len(sys.argv) > 1 else sys.stdin
try:
    for doc in yaml.safe_load_all(src):
        print(json.dumps(doc, indent=2))
except yaml.YAMLError as e:
    print(f"YAML ERROR: {e}", file=sys.stderr)
    sys.exit(1)
