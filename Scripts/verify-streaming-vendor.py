#!/usr/bin/env python3
"""Verify downloaded dependencies without changing them."""
from bootstrap import ROOT, bootstrap
bootstrap(ROOT, check=True)
