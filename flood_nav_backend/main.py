# main.py
import os
import glob
import httpx
import numpy as np
import rasterio
import rasterio.features
import rasterio.windows
import geopandas as gpd
from shapely.geometry import box, shape, mapping, Polygon, MultiPolygon, LineString
from shapely.ops import unary_union
from fastapi import FastAPI, Query
from datetime import datetime

app = FastAPI(title="Flood-Aware Navigation API", version="0.5.2")

DEM_PATH = "data/metro_manila_dem.tif"
NOAH_DIR = "data/noah"

dem_src = None
noah_gdf = None

VEHICLE_THRESHOLDS = {
    "motorcycle": {"passable": 10.0, "caution": 20.0},
    "sedan": {"passable": 15.0, "caution": 30.0},
    "suv": {"passable": 30.0, "caution": 50.0},
    "pickup": {"passable": 30.0, "caution": 50.0},
    "truck": {"passable": 50.0, "caution": 80.0},
    "bus": {"passable": 50.0, "caution": 80.0},
}

def evaluate_vehicle_passability(depth_cm: float, selected_vehicle: str = "sedan") -> dict:
    v_type = selected_vehicle.lower()
    rules = VEHICLE_THRESHOLDS.get(v_type, VEHICLE_THRESHOLDS["sedan"])

    if depth_cm < rules["passable"]:
        selected_severity = "passable"
    elif depth_cm <= rules["caution"]:
        selected_severity = "caution"
    else:
        selected_severity = "impassable"

    breakdown = {
        v: ("passable" if depth_cm < t["passable"] else "caution" if depth_cm <= t["caution"] else "impassable")
        for v, t in VEHICLE_THRESHOLDS.items()
    }

    return {"severity": selected_severity, "passability_by_vehicle": breakdown}

@app.on_event("startup")
def startup():
    global dem_src, noah_gdf
    if os.path.exists(DEM_PATH):
        try:
            dem_src = rasterio.open(DEM_PATH)
            print(f"✓ DEM Loaded: {DEM_PATH}")
        except Exception as e:
            print(f"✗ DEM load error: {e}")

    shp_files = glob.glob(f"{NOAH_DIR}/**/*.shp", recursive=True) + glob.glob(f"{NOAH_DIR}/**/*.geojson", recursive=True)
    if shp_files:
        try:
            gdf = gpd.read_file(shp_files[0])
            if gdf.crs is not None and gdf.crs.to_epsg() != 4326:
                gdf = gdf.to_crs(epsg=4326)
            noah_gdf = gdf
            print(f"✓ UP NOAH Loaded: {len(noah_gdf)} polygons indexed")
        except Exception as e:
            print(f"✗ NOAH load error: {e}")

@app.on_event("shutdown")
def shutdown():
    global dem_src
    if dem_src:
        dem_src.close()

async def get_forecast_profile(lat: float, lon: float) -> dict:
    try:
        url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={lat}&longitude={lon}"
            f"&hourly=precipitation"
            f"&current=precipitation"
            f"&timezone=Asia%2FManila"
            f"&forecast_days=1"
        )
        async with httpx.AsyncClient(timeout=4.0) as client:
            res = await client.get(url)
            if res.status_code == 200:
                data = res.json()
                current_rain = float(data.get("current", {}).get("precipitation", 0.0))
                hourly_precip = data.get("hourly", {}).get("precipitation", [])
                next_hour_rain = float(hourly_precip[1]) if len(hourly_precip) > 1 else current_rain
                effective_rate = current_rain + (0.5 * next_hour_rain)
                return {"current_rate_mm": current_rain, "effective_rate_mm": effective_rate}
    except Exception as e:
        print(f"Forecast error: {e}")
    return {"current_rate_mm": 0.0, "effective_rate_mm": 0.0}

@app.get("/hazards")
async def get_dynamic_hazards(
    south: float = Query(...),
    west: float = Query(...),
    north: float = Query(...),
    east: float = Query(...),
    path: str = Query(None),
    buffer_meters: float = Query(350.0),
    vehicle_type: str = Query("sedan"),
    simulate_rain: float = Query(None)
):
    center_lat = (south + north) / 2.0
    center_lon = (west + east) / 2.0

    weather = await get_forecast_profile(center_lat, center_lon)
    effective_rain = simulate_rain if simulate_rain is not None else weather["effective_rate_mm"]

    if effective_rain < 7.5:
        return {
            "type": "FeatureCollection",
            "vehicle_selected": vehicle_type,
            "weather_summary": {
                "rainfall_mm": round(effective_rain, 2),
                "status": "Dry / Normal Passability" if effective_rain < 1.0 else "Light Rain (Passable)"
            },
            "features": []
        }

    buffer_deg = buffer_meters / 111000.0
    if path:
        try:
            raw_pts = [list(map(float, pt.split(","))) for pt in path.split(";") if "," in pt]
            if len(raw_pts) >= 2:
                step = max(1, len(raw_pts) // 50)
                sampled_pts = raw_pts[::step]
                if sampled_pts[-1] != raw_pts[-1]:
                    sampled_pts.append(raw_pts[-1])
                filter_geom = LineString(sampled_pts).buffer(buffer_deg)
            else:
                filter_geom = box(west, south, east, north)
        except Exception:
            filter_geom = box(west, south, east, north)
    else:
        filter_geom = box(west, south, east, north)

    f_west, f_south, f_east, f_north = filter_geom.bounds
    raw_polygons = []

    # 1. UP NOAH Geometries
    if noah_gdf is not None:
        try:
            candidate_noah = noah_gdf.cx[f_west:f_east, f_south:f_north]
            for _, row in candidate_noah.iterrows():
                if row.geometry.intersects(filter_geom):
                    inter = row.geometry.intersection(filter_geom)
                    if not inter.is_empty:
                        if isinstance(inter, (Polygon, MultiPolygon)):
                            raw_polygons.append(inter)
        except Exception as e:
            print(f"NOAH processing error: {e}")

    # 2. DEM Geometries
    if dem_src is not None and effective_rain >= 20.0:
        try:
            b = dem_src.bounds
            c_west, c_south = max(f_west, b.left), max(f_south, b.bottom)
            c_east, c_north = min(f_east, b.right), min(f_north, b.top)
            if c_west < c_east and c_south < c_north:
                window = rasterio.windows.from_bounds(c_west, c_south, c_east, c_north, dem_src.transform)
                elevation = dem_src.read(1, window=window)
                win_transform = rasterio.windows.transform(window, dem_src.transform)
                flood_mask = (elevation > 0.5) & (elevation < 6.0)
                shapes = rasterio.features.shapes(flood_mask.astype(np.int16), mask=flood_mask, transform=win_transform)
                for geom, value in shapes:
                    if value == 1:
                        poly = shape(geom)
                        if poly.area > 0.000005 and poly.intersects(filter_geom):
                            raw_polygons.append(poly.intersection(filter_geom))
        except Exception as e:
            print(f"DEM processing error: {e}")

    if not raw_polygons:
        return {"type": "FeatureCollection", "vehicle_selected": vehicle_type, "features": []}

    # 3. CLUSTER GENERALIZATION: Merge touching parts while keeping discrete road clusters separate
    merged_union = unary_union(raw_polygons)
    
    if isinstance(merged_union, Polygon):
        distinct_islands = [merged_union]
    elif isinstance(merged_union, MultiPolygon):
        distinct_islands = list(merged_union.geoms)
    else:
        distinct_islands = []

    estimated_depth_cm = min(80.0, 15.0 + (effective_rain * 1.2))
    eval_res = evaluate_vehicle_passability(estimated_depth_cm, vehicle_type)

    if eval_res["severity"] == "passable":
        return {"type": "FeatureCollection", "vehicle_selected": vehicle_type, "features": []}

    features = []
    zone_count = 1

    for poly in distinct_islands:
        # Filter out negligible noise (< ~150 sq meters)
        if poly.area < 0.000015:
            continue

        # Smooth boundary slightly without expanding area
        simplified_island = poly.simplify(0.0004, preserve_topology=True)
        if simplified_island.is_empty:
            continue

        features.append({
            "type": "Feature",
            "geometry": mapping(simplified_island),
            "properties": {
                "id": f"hazard_cluster_{zone_count}",
                "source": "UP NOAH / Topographic Runoff",
                "severity": eval_res["severity"],
                "water_depth_cm": round(estimated_depth_cm, 1),
                "rainfall_rate_mm": effective_rain,
                "vehicle_type": vehicle_type,
            }
        })
        zone_count += 1

    return {
        "type": "FeatureCollection",
        "vehicle_selected": vehicle_type,
        "features": features
    }