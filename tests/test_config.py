"""Tests for config loading and saving."""

from pathlib import Path

from jpresume.config import load_config, save_config
from jpresume.models import JapanConfig, JapaneseAddress


def test_load_config(tmp_path, sample_config_data):
    import yaml

    config_path = tmp_path / "config.yaml"
    config_path.write_text(yaml.dump(sample_config_data, allow_unicode=True))

    config = load_config(config_path)
    assert config is not None
    assert config.name_kanji == "ドウ ジェーン"
    assert config.address_current.prefecture == "東京都"


def test_load_config_missing(tmp_path):
    config = load_config(tmp_path / "nonexistent.yaml")
    assert config is None


def test_save_and_load_roundtrip(tmp_path):
    config = JapanConfig(
        name_kanji="テスト太郎",
        name_furigana="テストタロウ",
        phone="090-0000-0000",
        address_current=JapaneseAddress(
            postal_code="100-0001",
            prefecture="東京都",
            city="千代田区",
        ),
    )

    path = tmp_path / "test_config.yaml"
    save_config(config, path)

    loaded = load_config(path)
    assert loaded is not None
    assert loaded.name_kanji == "テスト太郎"
    assert loaded.address_current.prefecture == "東京都"
