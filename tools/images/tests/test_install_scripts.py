"""Exercise shared installer arguments and SSH policy without system changes.

Notes
-----
Privileged commands are replaced with shell functions before running script text.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture
def bash() -> str:
    """Locate Bash for isolated script execution.

    Returns
    -------
    str
        Git Bash on Windows, or the system Bash elsewhere.
    """
    for candidate in ("C:/h/Git/bin/bash.exe", "C:/Program Files/Git/bin/bash.exe"):
        if Path(candidate).is_file():
            return candidate
    executable = shutil.which("bash")
    if executable is None:
        pytest.skip()
    return executable


def run_script(bash: str, script: str, args: list[str]) -> subprocess.CompletedProcess[str]:
    """Run supplied shell text with explicit positional arguments.

    Parameters
    ----------
    bash : str
        Bash executable.
    script : str
        Script text, optionally preceded by command replacements.
    args : list[str]
        Arguments exposed to the script.

    Returns
    -------
    subprocess.CompletedProcess[str]
        Captured status and output.
    """
    return subprocess.run(
        [bash, "--noprofile", "--norc", "-s", "--", *args],
        input=script,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )


@pytest.mark.parametrize(
    "relative,option",
    [
        ("system/user.sh", "--groups"),
        ("system/ssh.sh", "--mode"),
        ("dev/precommit.sh", "--config"),
        ("integrations/ros2.sh", "--distro"),
        *(
            (f"libraries/{name}.sh", "--version")
            for name in ("cpptrace", "iceoryx", "libdatachannel", "rpclib")
        ),
    ],
)
def test_installer_arguments(bash: str, relative: str, option: str) -> None:
    """Reject malformed arguments before installation begins.

    Parameters
    ----------
    bash, relative, option : str
        Bash executable, installer path and a value-taking option.
    """
    script = (ROOT / "vendor/image-kit/scripts" / relative).read_text(encoding="utf-8")
    assert run_script(bash, script, ["--help"]).returncode == 0
    for args in (["--unknown"], [option], ["unexpected-positional"]):
        result = run_script(bash, script, args)
        assert result.returncode == 64, result.stderr


@pytest.mark.parametrize("groups,expected", [("", 0), ("video", 64), ("video,,render", 64)])
def test_root_groups(bash: str, groups: str, expected: int) -> None:
    """Permit root reuse only without supplementary groups.

    Parameters
    ----------
    bash, groups : str
        Bash executable and requested group list.
    expected : int
        Expected exit status.
    """
    script = (ROOT / "vendor/image-kit/scripts/system/user.sh").read_text(encoding="utf-8")
    result = run_script(bash, script, ["--username", "root", "--groups", groups])
    assert result.returncode == expected, result.stderr


@pytest.mark.parametrize("user", ["root", "luciole"])
@pytest.mark.parametrize("mode", ["disabled", "key-only", "password"])
def test_ssh_policy(bash: str, tmp_path: Path, user: str, mode: str) -> None:
    """Keep build-time and runtime SSH policy aligned for both account types.

    Parameters
    ----------
    bash, user, mode : str
        Bash executable, selected account and authentication mode.
    tmp_path : pathlib.Path
        Isolated configuration, key and password files.
    """
    # All privileged commands are inert. Only the generated config uses a real file.
    preamble = """
apt-get() { :; }; rm() { :; }; mkdir() { :; }; chmod() { :; }
chown() { :; }; touch() { :; }; ssh-keygen() { :; }
id() { if [ "$1" = -u ]; then echo 0; else echo root; fi; }
getent() { printf '%s:x:1000:1000::.:/bin/bash\n' "$2"; }
mock_sshd() { printf '%s\n' "$@"; }
chpasswd() { cat >/dev/null; }; export -f chpasswd
"""
    config = tmp_path / "sshd.conf"
    installer = (ROOT / "vendor/image-kit/scripts/system/ssh.sh").read_text(encoding="utf-8")
    installer = installer.replace("/etc/ssh/sshd_config.d/99-dev-image.conf", '"${TEST_CONFIG}"')
    # Consume the test output path before the real option parser sees its arguments.
    result = run_script(
        bash,
        preamble + '\nTEST_CONFIG="$1"; shift\n' + installer,
        [config.as_posix(), "--default-user", user, "--mode", mode],
    )
    assert result.returncode == 0, result.stderr
    permit = {"disabled": "no", "key-only": "prohibit-password", "password": "yes"}
    expected = permit[mode] if user == "root" else "no"
    assert f"PermitRootLogin {expected}\n" in config.read_text(encoding="utf-8")

    key = tmp_path / "authorized_keys"
    key.write_text("test public key\n", encoding="utf-8")
    password = tmp_path / "password"
    password.write_text("test password\n", encoding="utf-8")
    entrypoint = (ROOT / "vendor/image-kit/assets/docker-entrypoint.sh").read_text(encoding="utf-8")
    entrypoint = entrypoint.replace("/usr/sbin/sshd", "mock_sshd")
    entrypoint = entrypoint.replace('"${USER_HOME}/.ssh/authorized_keys"', '"${TEST_KEY}"')
    setup = '\nDEFAULT_USER="$1"; SSH_MODE="$2"; TEST_KEY="$3"; SSH_PASSWORD_FILE="$4"\n'
    setup += "shift 4; unset BASH_ENV\n"
    result = run_script(
        bash,
        preamble + setup + entrypoint,
        [user, mode, key.as_posix(), password.as_posix(), "echo", "command-executed"],
    )
    assert result.returncode == 0, result.stderr
    assert "command-executed" in result.stdout
    if mode != "disabled":
        assert f"PermitRootLogin={expected}" in result.stdout

    if user == "root" and mode == "password":
        result = run_script(
            bash,
            preamble + setup + entrypoint,
            [user, mode, key.as_posix(), "", "echo", "command-executed"],
        )
        assert result.returncode == 64
        assert "requires SSH_PASSWORD_FILE" in result.stderr
        assert "command-executed" not in result.stdout

    if mode == "key-only":
        key.write_text("", encoding="utf-8")
        result = run_script(
            bash,
            preamble + setup + entrypoint,
            [user, mode, key.as_posix(), password.as_posix(), "echo", "command-executed"],
        )
        assert result.returncode == 64
        assert "requires a non-empty" in result.stderr
        assert "command-executed" not in result.stdout
        result = run_script(
            bash,
            preamble + "\nSSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true\n" + setup + entrypoint,
            [user, mode, key.as_posix(), password.as_posix(), "echo", "command-executed"],
        )
        assert result.returncode == 0, result.stderr
        assert "SSH awaits a public key" in result.stderr
        assert "command-executed" in result.stdout
        assert "PasswordAuthentication=no" in result.stdout


@pytest.mark.parametrize("groups", ["", "video,render"])
def test_user_groups(bash: str, tmp_path: Path, groups: str) -> None:
    """Forward optional supplementary groups to account creation.

    Parameters
    ----------
    bash, groups : str
        Bash executable and supplementary group list.
    tmp_path : pathlib.Path
        Isolated sudoers output.
    """
    preamble = """
getent() { return 1; }; groupadd() { :; }; passwd() { :; }
apt-get() { :; }; rm() { :; }; mkdir() { :; }; chmod() { :; }; chown() { :; }
useradd() { printf '%s\n' "$@"; }
TEST_SUDOERS="$1"; shift
"""
    script = (ROOT / "vendor/image-kit/scripts/system/user.sh").read_text(encoding="utf-8")
    script = script.replace('/etc/sudoers.d/"${USERNAME_VAL}"', '"${TEST_SUDOERS}"')
    result = run_script(
        bash,
        preamble + script,
        [(tmp_path / "sudoers").as_posix(), "--username", "luciole", "--groups", groups],
    )
    assert result.returncode == 0, result.stderr
    if groups:
        assert f"--groups\n{groups}\n" in result.stdout
    else:
        assert "--groups" not in result.stdout


def test_local_extensions(bash: str, tmp_path: Path) -> None:
    """Exercise local apt additions and delegation to the shared CUDA installer.

    Parameters
    ----------
    bash : str
        Bash executable.
    tmp_path : pathlib.Path
        Isolated installer and requirements files.
    """
    apt = (ROOT / "src/_scripts/dev/luciole-dev-tools.sh").read_text(encoding="utf-8")
    for args, expected in [(["--help"], 0), (["--unknown"], 64), (["unexpected"], 64)]:
        assert run_script(bash, apt, args).returncode == expected
    result = run_script(bash, 'apt-get() { printf "%s\\n" "$@"; }; rm() { :; }\n' + apt, [])
    assert result.returncode == 0, result.stderr
    assert "landscape-common\nsudo\n" in result.stdout
    assert "gosu" not in result.stdout

    requirements = tmp_path / "requirements.txt"
    requirements.write_text("example-package\n", encoding="utf-8")
    common = tmp_path / "cuda-pip-packages.sh"
    common.write_text(
        (ROOT / "vendor/image-kit/scripts/python/cuda-pip-packages.sh").read_text(encoding="utf-8"),
        encoding="utf-8",
        newline="\n",
    )
    common.chmod(0o755)
    wrapper = (ROOT / "src/_scripts/python/luciole-cuda-pip-packages.sh").read_text(
        encoding="utf-8"
    )
    for args in ([], ["--requirements"], ["--requirements", "missing"], ["--unknown"]):
        assert run_script(bash, wrapper, args).returncode == 64
    preamble = """
python3() { printf '%s\\n' "$@"; }; export -f python3
TEST_INSTALLER_DIR="$1"; shift
dirname() { printf '%s' "${TEST_INSTALLER_DIR}"; }
"""
    result = run_script(
        bash,
        preamble + wrapper,
        [tmp_path.as_posix(), "--requirements", requirements.as_posix()],
    )
    assert result.returncode == 0, result.stderr
    assert "--upgrade\npip\n" in result.stdout
    assert "--ignore-installed\npsutil\n" in result.stdout
    assert f"--requirement\n{requirements.as_posix()}\n" in result.stdout
