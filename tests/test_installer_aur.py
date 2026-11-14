"""AUR installation must leave stdin available for sudo authentication."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class AurBootstrapTest(unittest.TestCase):
    def test_makepkg_can_read_authentication_from_stdin(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (bin_dir / "git").write_text('#!/bin/bash\nmkdir -p "${@: -1}"\n')
            (bin_dir / "makepkg").write_text(
                '#!/bin/bash\nread -r password\n[[ "$password" == secret ]]\n'
            )
            (bin_dir / "sudo").write_text('#!/bin/bash\nexit 0\n')
            for name in ("git", "makepkg", "sudo"):
                (bin_dir / name).chmod(0o755)

            script = """
source <(sed '$d' setup.sh)
DRYRUN=0
ANIM=0
COLOR=0
init_style
LOG="$TEST_LOG"
FACT_AUR=""
DO_AUR_HELPER=1
bootstrap_aur_helper
[[ "$FACT_AUR" == yay ]]
"""
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=REPO,
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
                     "TEST_LOG": str(root / "install.log")},
                input="secret\n",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_yay_can_read_authentication_from_stdin(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (bin_dir / "sudo").write_text('#!/bin/bash\nexit 0\n')
            (bin_dir / "yay").write_text(
                '#!/bin/bash\nread -r password\n[[ "$password" == secret ]]\n'
            )
            for name in ("sudo", "yay"):
                (bin_dir / name).chmod(0o755)

            script = """
source <(sed '$d' setup.sh)
DRYRUN=0
ANIM=0
COLOR=0
init_style
LOG="$TEST_LOG"
FACT_AUR=yay
PACMAN_LIST=()
AUR_LIST=(example-aur-package)
install_packages
"""
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=REPO,
                env={**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
                     "TEST_LOG": str(root / "install.log")},
                input="secret\n",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
