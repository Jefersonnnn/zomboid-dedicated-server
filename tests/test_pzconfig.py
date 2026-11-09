"""Tests for src/pzconfig.py."""

import importlib.util
import json
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "pzconfig", Path(__file__).resolve().parents[1] / "src" / "pzconfig.py"
)
pzconfig = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(pzconfig)

INI = "# comment\nPVP=true\nPassword=\nMaxPlayers=32\nMods=\n"


class TestSetIniValue:
    def test_replaces_only_target_line(self):
        text, changed = pzconfig.set_ini_value(INI, "MaxPlayers", "4")
        assert changed
        assert text == INI.replace("MaxPlayers=32", "MaxPlayers=4")

    def test_unchanged_value_reports_no_change(self):
        text, changed = pzconfig.set_ini_value(INI, "PVP", "true")
        assert not changed
        assert text == INI

    def test_does_not_match_key_prefix(self):
        with pytest.raises(pzconfig.KeyNotFoundError):
            pzconfig.set_ini_value("MaxPlayersX=1\n", "MaxPlayers", "4")

    def test_missing_key_raises(self):
        with pytest.raises(pzconfig.KeyNotFoundError):
            pzconfig.set_ini_value(INI, "UDPPort", "16262")

    def test_preserves_crlf(self):
        text, _ = pzconfig.set_ini_value("A=1\r\nB=2\r\n", "A", "9")
        assert text == "A=9\r\nB=2\r\n"

    def test_value_with_semicolons_and_equals(self):
        text, _ = pzconfig.set_ini_value(INI, "Mods", "a;b=c")
        assert "Mods=a;b=c\n" in text

    def test_rejects_multiline_value(self):
        with pytest.raises(ValueError):
            pzconfig.set_ini_value(INI, "Password", "a\nPVP=false")


class TestSetJvmHeap:
    def test_replaces_existing_xmx_and_keeps_other_flags(self):
        config = {"vmArgs": ["-Xmx8g", "-XX:+UseZGC", "-Dfoo=1"]}
        assert pzconfig.set_jvm_heap(config, "4g")
        assert config["vmArgs"] == ["-Xmx4g", "-XX:+UseZGC", "-Dfoo=1"]

    def test_adds_xmx_when_missing(self):
        config = {"vmArgs": ["-XX:+UseZGC"]}
        assert pzconfig.set_jvm_heap(config, "4096m")
        assert config["vmArgs"][0] == "-Xmx4096m"

    def test_no_change_when_already_set(self):
        config = {"vmArgs": ["-Xmx4g", "-XX:+UseZGC"]}
        assert not pzconfig.set_jvm_heap(config, "4g")

    @pytest.mark.parametrize("size", ["4", "0g", "4gb", "-4g", ""])
    def test_rejects_invalid_size(self, size):
        with pytest.raises(ValueError):
            pzconfig.set_jvm_heap({"vmArgs": []}, size)

    def test_rejects_missing_vmargs(self):
        with pytest.raises(ValueError):
            pzconfig.set_jvm_heap({}, "4g")


class TestCli:
    def test_ini_set_writes_file_and_keeps_mode(self, tmp_path):
        ini = tmp_path / "server.ini"
        ini.write_text(INI)
        ini.chmod(0o640)
        assert pzconfig.main(["ini-set", str(ini), "MaxPlayers", "4"]) == 0
        assert "MaxPlayers=4\n" in ini.read_text()
        assert ini.stat().st_mode & 0o777 == 0o640

    def test_ini_set_missing_key_exit_code(self, tmp_path):
        ini = tmp_path / "server.ini"
        ini.write_text(INI)
        assert pzconfig.main(["ini-set", str(ini), "Nope", "1"]) == pzconfig.EXIT_KEY_NOT_FOUND
        assert ini.read_text() == INI

    def test_jvm_heap_cli(self, tmp_path):
        cfg = tmp_path / "ProjectZomboid64.json"
        cfg.write_text(json.dumps({"mainClass": "x", "vmArgs": ["-Xmx16g"]}))
        assert pzconfig.main(["jvm-heap", str(cfg), "4g"]) == 0
        assert json.loads(cfg.read_text())["vmArgs"] == ["-Xmx4g"]

    def test_missing_file_is_error(self, tmp_path):
        assert pzconfig.main(["jvm-heap", str(tmp_path / "x.json"), "4g"]) == pzconfig.EXIT_ERROR
