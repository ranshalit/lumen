import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DockerBuildHelperTests(unittest.TestCase):
    def test_preserves_absolute_build_path(self):
        project_dir = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporary_dir:
            temporary_path = Path(temporary_dir)
            docker = temporary_path / "docker"
            docker.write_text(
                '#!/bin/sh\n'
                'if [ "$1" = run ]; then printf "%s\\n" "$@"; fi\n'
            )
            docker.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                PATH=f"{temporary_path}:{environment['PATH']}",
                LUMEN_DL_CACHE=str(temporary_path),
                LUMEN_SSTATE_CACHE=str(temporary_path),
            )
            result = subprocess.run(
                ["sh", str(project_dir / "build-in-docker.sh"), "lumen-orin-nx-16gb"],
                env=environment,
                cwd=temporary_path,
                capture_output=True,
                text=True,
                check=True,
            )
            arguments = result.stdout.splitlines()
            self.assertEqual(arguments[arguments.index("-w") + 1], str(project_dir))
            self.assertIn(f"{project_dir}:{project_dir}", arguments)


if __name__ == "__main__":
    unittest.main()
