import importlib.util
from pathlib import Path
import hashlib
import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


IMAGE = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/brain-tasks@sha256:" + "a" * 64
API_IMAGE = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/brain-tasks-api@sha256:" + "b" * 64


def test_release_resolves_both_images_and_limits_network_exposure():
    text = load("render-manifests").render(IMAGE, API_IMAGE, source_cidrs="192.0.2.10/32")
    assert "__" not in text
    docs = list(yaml.safe_load_all(text))
    deployments = [doc for doc in docs if doc["kind"] == "Deployment"]
    assert {doc["spec"]["template"]["spec"]["containers"][0]["image"] for doc in deployments} == {IMAGE, API_IMAGE}
    service = next(doc for doc in docs if doc["kind"] == "Service" and doc["metadata"]["name"] == "brain-tasks")
    assert service["spec"]["loadBalancerSourceRanges"] == ["192.0.2.10/32"]
    assert all(doc["metadata"]["namespace"] == "brain-tasks" for doc in docs)
    assert len(docs) == 7


def test_tls_render_has_issued_certificate_annotation_and_tls_port():
    arn = "arn:aws:acm:ap-south-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    docs = list(yaml.safe_load_all(load("render-manifests").render(IMAGE, API_IMAGE, arn, "192.0.2.10/32")))
    service = next(doc for doc in docs if doc["kind"] == "Service" and doc["metadata"]["name"] == "brain-tasks")
    assert service["metadata"]["annotations"]["service.beta.kubernetes.io/aws-load-balancer-ssl-cert"] == arn
    assert {port["port"] for port in service["spec"]["ports"]} == {3000, 443}


def test_mutable_images_and_missing_network_allowlist_are_rejected():
    render = load("render-manifests").render
    with pytest.raises(ValueError):
        render(IMAGE.replace("@sha256:" + "a" * 64, ":latest"), API_IMAGE, source_cidrs="192.0.2.10/32")
    with pytest.raises(ValueError):
        render(IMAGE, API_IMAGE)


def test_upstream_is_preserved_and_prepared_bundle_uses_owned_api(tmp_path):
    original = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / "dist").rglob("*") if p.is_file()}
    load("prepare-dist").prepare(ROOT / "dist", tmp_path / "prepared")
    assert original == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / "dist").rglob("*") if p.is_file()}
    js = next((tmp_path / "prepared/assets").glob("*.js")).read_text()
    assert "mockapi.io/api/v1/tasks" not in js
    assert js.count("/api/v1/tasks") == 5
    assert js.count('window.location.assign("/")') == 3
