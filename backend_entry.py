#!/usr/bin/env python3
"""PyInstaller entry point that preserves backend package imports."""

print("PROGRESS 0.005 Packaged runtime started", flush=True)

from backend.cli import main


if __name__ == "__main__":
    main()
