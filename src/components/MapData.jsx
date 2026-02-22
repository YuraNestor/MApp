import { useState, useEffect, useMemo, useCallback } from 'react';
import Map, { Source, Layer, Marker, Popup, NavigationControl } from 'react-map-gl/maplibre';
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';

// Base map styles mapping to MapTiler or similar free styles
const getStyleConfig = (type) => {
    const rasterSources = {
        dark: 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
        light: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        satellite: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
    };

    return {
        version: 8,
        sources: {
            'raster-tiles': {
                type: 'raster',
                tiles: [rasterSources[type] || rasterSources.dark],
                tileSize: 256,
                attribution: 'Map data &copy; OpenStreetMap contributors'
            }
        },
        layers: [
            {
                id: 'simple-tiles',
                type: 'raster',
                source: 'raster-tiles',
                minzoom: 0,
                maxzoom: 22
            }
        ]
    };
};

const getDistance = (lat1, lon1, lat2, lon2) => {
    const R = 6371e3; // metres
    const φ1 = lat1 * Math.PI / 180;
    const φ2 = lat2 * Math.PI / 180;
    const Δφ = (lat2 - lat1) * Math.PI / 180;
    const Δλ = (lon2 - lon1) * Math.PI / 180;

    const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
        Math.cos(φ1) * Math.cos(φ2) *
        Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c;
};

export default function MapData({ points, currentPos, mapStyle = 'dark', followUser, onMapDrag, sensitivity = 1.0, speedInfluence = 0.5, destination, routeGeometry, onSetDestination }) {

    // Manage ViewState manually for smooth following and 3D effects
    const [viewState, setViewState] = useState({
        longitude: -0.09,
        latitude: 51.505,
        zoom: 15,
        pitch: 0,
        bearing: 0
    });

    const isNavigating = destination != null && currentPos != null;

    // Follow User Logic & Navigation Mode Sync
    useEffect(() => {
        if (currentPos && followUser) {
            setViewState(prev => ({
                ...prev,
                longitude: currentPos.lng,
                latitude: currentPos.lat,
                pitch: isNavigating ? 60 : 0,
                // Only rotate the map to heading when in active navigation mode
                bearing: isNavigating ? (currentPos.heading || 0) : 0,
                // Optional: zoom in slightly during navigation
                zoom: isNavigating && prev.zoom < 16 ? 16 : prev.zoom,
            }));
        }
    }, [currentPos, followUser, isNavigating]);

    const handleMove = useCallback(evt => {
        setViewState(evt.viewState);
    }, []);

    const handleMoveStart = useCallback((evt) => {
        // If the move was caused by the user dragging/touching the map, disable follow mode
        if (evt.originalEvent) {
            onMapDrag();
        }
    }, [onMapDrag]);

    const handleMapClick = useCallback((evt) => {
        if (!isNavigating && evt.lngLat) {
            onSetDestination({ lat: evt.lngLat.lat, lng: evt.lngLat.lng });
        }
    }, [isNavigating, onSetDestination]);

    // Format Point Data for GeoJSON to render efficiently and construct colored route
    const { pointData, routeData, directionalPointsVisible } = useMemo(() => {
        const pData = [];
        const dirPoints = [];
        const rDataFeatures = [];

        // Precalculate colors for all points
        const pointsWithMeta = points.map(p => {
            let adjustedRoughness = p.roughness * sensitivity;
            if (p.speed !== undefined && p.speed !== null) {
                const speed = p.speed;
                let speedFactor = (speed - 20) / (100 - 20);
                if (speedFactor < 0) speedFactor = 0;
                if (speedFactor > 1) speedFactor = 1;
                adjustedRoughness = adjustedRoughness * (1 - (speedFactor * speedInfluence));
            }

            let color = '#ff0000';
            if (adjustedRoughness < 2) color = '#00ff00';
            else if (adjustedRoughness < 5) color = '#ffff00';
            else if (adjustedRoughness < 8) color = '#ffa500';

            return { ...p, color, usedInRoute: false };
        });

        // If we have a route, build it out of line segments, coloring by close points
        if (routeGeometry && routeGeometry.length > 0) {
            const routeCoords = routeGeometry.map(coord => [coord[1], coord[0]]); // [lat, lng] to [lng, lat]

            for (let i = 0; i < routeCoords.length - 1; i++) {
                const start = routeCoords[i];
                const end = routeCoords[i + 1];

                const midLng = (start[0] + end[0]) / 2;
                const midLat = (start[1] + end[1]) / 2;

                let closestPointIdx = -1;
                let minDistance = Infinity;

                for (let j = 0; j < pointsWithMeta.length; j++) {
                    const p = pointsWithMeta[j];
                    // Fast bounding box check (~50 meters)
                    if (Math.abs(p.lat - midLat) > 0.0005 || Math.abs(p.lng - midLng) > 0.0005) continue;

                    const dist = getDistance(midLat, midLng, p.lat, p.lng);
                    if (dist < minDistance) {
                        minDistance = dist;
                        closestPointIdx = j;
                    }
                }

                let segmentColor = '#3b82f6'; // Default blue

                // If a road quality point is within 25 meters, snap that color to the route
                if (closestPointIdx !== -1 && minDistance < 25) {
                    segmentColor = pointsWithMeta[closestPointIdx].color;
                    pointsWithMeta[closestPointIdx].usedInRoute = true;
                }

                rDataFeatures.push({
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [start, end]
                    },
                    properties: { color: segmentColor }
                });
            }
        }

        // Add unused points back to display list
        for (const p of pointsWithMeta) {
            if (!p.usedInRoute) {
                pData.push({
                    type: 'Feature',
                    geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
                    properties: { color: p.color, heading: p.heading, speed: p.speed }
                });

                if (p.speed > 1 && p.heading !== undefined && p.heading !== null) {
                    dirPoints.push(p);
                }
            }
        }

        return {
            pointData: { type: 'FeatureCollection', features: pData },
            routeData: rDataFeatures.length > 0 ? { type: 'FeatureCollection', features: rDataFeatures } : null,
            directionalPointsVisible: dirPoints
        };

    }, [points, routeGeometry, sensitivity, speedInfluence]);


    return (
        <div className="maplibre-container">
            <Map
                {...viewState}
                onMove={handleMove}
                onMoveStart={handleMoveStart}
                onClick={handleMapClick}
                mapStyle={getStyleConfig(mapStyle)}
                style={{ width: '100%', height: '100%' }}
                interactiveLayerIds={['points-layer']}
                mapLib={maplibregl}
            >
                <NavigationControl position="bottom-right" showCompass={true} showZoom={false} />

                {/* Draw Route (Colored Segments) */}
                {routeData && (
                    <Source id="route" type="geojson" data={routeData}>
                        <Layer
                            id="route-line"
                            type="line"
                            paint={{
                                'line-color': ['get', 'color'],
                                'line-width': 6,
                                'line-opacity': 0.8
                            }}
                        />
                    </Source>
                )}

                {/* Draw Points (Circles) - Simple Data Layer */}
                <Source id="points" type="geojson" data={pointData}>
                    <Layer
                        id="points-circles"
                        type="circle"
                        paint={{
                            'circle-color': ['get', 'color'],
                            'circle-radius': 5,
                            'circle-opacity': 0.7
                        }}
                        filter={['!', ['has', 'heading']]} // Only points without heading
                    />
                </Source>

                {/* HTML Markers for Directional Points */}
                {directionalPointsVisible.map((p, idx) => {
                    return (
                        <Marker key={`dir-${idx}`} longitude={p.lng} latitude={p.lat} anchor="center">
                            <div style={{ transform: `rotate(${p.heading}deg)`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                <svg width="14" height="14" viewBox="0 0 24 24" fill={p.color} stroke="#000" strokeWidth="1">
                                    <path d="M12 2L22 22L12 18L2 22Z" />
                                </svg>
                            </div>
                        </Marker>
                    );
                })}


                {/* Destination Marker */}
                {destination && (
                    <Marker longitude={destination.lng} latitude={destination.lat} anchor="bottom">
                        <Popup longitude={destination.lng} latitude={destination.lat} closeButton={false} anchor="top" style={{ marginTop: '10px' }}>
                            <div style={{ color: '#000', fontWeight: 'bold' }}>{destination.name}</div>
                        </Popup>
                        <div style={{ color: '#ef4444', marginTop: '-24px' }}>
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor" stroke="white" strokeWidth="2">
                                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
                                <circle cx="12" cy="10" r="3"></circle>
                            </svg>
                        </div>
                    </Marker>
                )}

                {/* Current Player Marker */}
                {currentPos && (
                    <Marker longitude={currentPos.lng} latitude={currentPos.lat} anchor="center" style={{ zIndex: 10 }}>
                        {isNavigating || (currentPos.speed > 1 && currentPos.heading !== undefined) ? (
                            <div style={{ transform: `rotate(${currentPos.heading}deg)` }}>
                                <svg width="32" height="32" viewBox="0 0 24 24" fill="#3b82f6" stroke="white" strokeWidth="2">
                                    <path d="M12 2L22 22L12 18L2 22Z" />
                                </svg>
                            </div>
                        ) : (
                            <div style={{
                                width: '16px', height: '16px', borderRadius: '50%',
                                background: '#3b82f6', border: '2px solid white',
                                boxShadow: '0 0 10px rgba(0,0,0,0.5)'
                            }} />
                        )}
                    </Marker>
                )}
            </Map>
        </div>
    );
}
