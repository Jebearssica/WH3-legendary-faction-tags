#!/usr/bin/env python3
"""用 lupa(内嵌 Lua) 跑 tests/lft_mock_test.lua 的离线单元测试。

需要: pip install lupa
用法: python tools/run_lua_tests.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:  # pragma: no cover
    print("缺少依赖, 请先运行: python -m pip install lupa", file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((root / "tests" / "lft_mock_test.lua").read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
