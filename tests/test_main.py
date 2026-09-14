from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_home_returns_200():
    """Verify the home page loads successfully."""
    response = client.get("/")
    assert response.status_code == 200


def test_home_contains_project_name():
    """Verify the home page contains our project branding."""
    response = client.get("/")
    assert "Project CCM" in response.text


def test_health_check():
    """Verify the health endpoint returns correct JSON."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "ccm-ec2-live"

