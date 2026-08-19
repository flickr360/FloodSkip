from fastapi import FastAPI, Query

app = FastAPI(
    title="Flood-Aware Navigation API",
    description="Backend API for flood-aware navigation.",
    version="0.1.0",
)


@app.get("/")
def root():
    return {
        "name": "Flood-Aware Navigation API",
        "status": "ok",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
    }


@app.get("/hazards")
def get_hazards(
    south: float = Query(...),
    west: float = Query(...),
    north: float = Query(...),
    east: float = Query(...),
):
    return {
        "hazards": [
            {
                "id": "test-flood-001",
                "polygon": [
                    [121.0200, 14.6050],
                    [121.0250, 14.6050],
                    [121.0250, 14.6100],
                    [121.0200, 14.6100],
                    [121.0200, 14.6050]
                ],
                "severity": "impassable",
                "source": "official",
                "reportedAt": "2026-08-19T02:00:00Z",
                "expiresAt": "2026-08-20T06:00:00Z",
                "confirmations": 0
            }
        ]
    }