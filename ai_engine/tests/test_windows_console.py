import os
import subprocess
import sys


def test_vietnamese_cli_with_legacy_stdout():
    result = subprocess.run(
        [sys.executable, "-X", "utf8=0", "-m", "ai_engine.scripts.make_fake_history", "--help"],
        env={**os.environ, "PYTHONIOENCODING": "cp1252"},
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert "Lịch sử giả" in result.stdout.decode("utf-8")
