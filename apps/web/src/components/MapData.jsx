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

import { getDistance, getPerpendicularDist, getColorFromRoughness } from '@mapp/shared';

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

    // 1) Precalculate colors for map points 
    // This updates frequently during recording
    const { pointData, directionalPointsVisible, pointsWithMeta } = useMemo(() => {
        const pData = [];
        const dirPoints = [];

        const pMeta = points.map(p => {
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

            return { ...p, adjustedRoughness, color };
        });

        // Add unused points back to display list
        for (const p of pMeta) {
            pData.push({
                type: 'Feature',
                geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
                // Use actual dynamic color calculation in next useMemo, just pass basic color for now
                properties: { color: p.color, heading: p.heading, speed: p.speed, roughness: p.adjustedRoughness }
            });

            if (p.speed > 1 && p.heading !== undefined && p.heading !== null) {
                dirPoints.push(p);
            }
        }

        return {
            pointData: { type: 'FeatureCollection', features: pData },
            directionalPointsVisible: dirPoints,
            pointsWithMeta: pMeta
        };
    }, [points, sensitivity, speedInfluence]);

    // 2) Heavy computation: Calculate gradient colors for route based on nearby points.
    // To avoid freezing UI during mobile recording, we separate this.
    // It still depends on pointsWithMeta, but we'll use a fast check.
    const routeData = useMemo(() => {
        if (!routeGeometry || routeGeometry.length === 0) return null;

        const rDataFeatures = [];

        const routeCoords = routeGeometry.map(coord => [coord[1], coord[0]]); // [lat, lng] to [lng, lat]

        // ViewState params for calculating level of detail (LOD) optimization
        const mapZoom = viewState.zoom || 15;
        const camLat = viewState.latitude;
        const camLng = viewState.longitude;

        for (let i = 0; i < routeCoords.length - 1; i++) {
            const start = routeCoords[i];
            const end = routeCoords[i + 1];

            const segmentLength = getDistance(start[1], start[0], end[1], end[0]);

            let chunkSize = 5; // Default best quality

            // Optimization: Distance from active camera coordinate
            const distToCamera = getDistance(camLat, camLng, start[1], start[0]);

            // Adjust chunk size drastically if we are zoomed out (mapZoom < 14)
            if (mapZoom < 10) {
                chunkSize = Math.max(chunkSize, 500);
            } else if (mapZoom < 12) {
                chunkSize = Math.max(chunkSize, 200);
            } else if (mapZoom < 14) {
                chunkSize = Math.max(chunkSize, 50);
            }

            // Adjust chunk size if the segment is far away from current viewport focus (useful in 3D tilt mode)
            // E.g. anything over 5km away gets rendered with 50m chunks
            if (distToCamera > 50000) {
                chunkSize = Math.max(chunkSize, 500);
            } else if (distToCamera > 10000) {
                chunkSize = Math.max(chunkSize, 100);
            } else if (distToCamera > 3000) {
                chunkSize = Math.max(chunkSize, 25);
            }

            // Split long segments into chunks to create a smooth gradient
            const numSplits = Math.max(1, Math.ceil(segmentLength / chunkSize));

            for (let k = 0; k < numSplits; k++) {
                const ratioStart = k / numSplits;
                const ratioEnd = (k + 1) / numSplits;

                const subStart = [
                    start[0] + (end[0] - start[0]) * ratioStart,
                    start[1] + (end[1] - start[1]) * ratioStart
                ];

                const subEnd = [
                    start[0] + (end[0] - start[0]) * ratioEnd,
                    start[1] + (end[1] - start[1]) * ratioEnd
                ];

                const midLng = (subStart[0] + subEnd[0]) / 2;
                const midLat = (subStart[1] + subEnd[1]) / 2;

                // Find points influencing this specific sub-segment
                let sumRoughness = 0;
                let totalWeight = 0;

                for (let j = 0; j < pointsWithMeta.length; j++) {
                    const p = pointsWithMeta[j];
                    // Fast bounding box check (~20m)
                    if (Math.abs(p.lat - midLat) > 0.0002 || Math.abs(p.lng - midLng) > 0.0002) continue;

                    const dist = getPerpendicularDist(p, subStart, subEnd);

                    // If the distance is strictly Infinity, it means the point's perpendicular
                    // projection doesn't fall linearly on THIS specific sub-segment.
                    // We strictly want to color based on perpendicular projections within 10 meters!
                    if (dist <= Math.max(10, chunkSize / 2)) { // expand check radius slightly if chunk is huge
                        // Weight by inverse distance (closer points have stronger color influence)
                        let weight = 1 / (dist + 1); // +1 to avoid division by zero
                        sumRoughness += p.adjustedRoughness * weight;
                        totalWeight += weight;
                        // For rendering logic separation we don't mutate `p` here anymore.
                    }
                }

                // Store null if no points influence it, so we can fill it in the second pass
                let subColor = null;

                if (totalWeight > 0) {
                    const avgRoughness = sumRoughness / totalWeight;
                    subColor = getColorFromRoughness(avgRoughness);
                }

                rDataFeatures.push({
                    type: 'Feature',
                    geometry: {
                        type: 'LineString',
                        coordinates: [subStart, subEnd]
                    },
                    properties: {
                        color: subColor,
                        originalColor: subColor
                    }
                });
            }
        }

        // Second pass: fill in short gaps (null colors) using nearest colored neighbors
        // If the gap is too long, we leave it as default blue.
        for (let i = 0; i < rDataFeatures.length; i++) {
            if (rDataFeatures[i].properties.color === null) {
                let prevColor = null;
                let nextColor = null;
                let gapSizeToPrev = 0;
                let gapSizeToNext = 0;

                // Find nearest previous colored segment
                for (let j = i - 1; j >= 0; j--) {
                    gapSizeToPrev++;
                    if (rDataFeatures[j].properties.originalColor !== null) {
                        prevColor = rDataFeatures[j].properties.originalColor;
                        break;
                    }
                }

                // Find nearest next colored segment
                for (let j = i + 1; j < rDataFeatures.length; j++) {
                    gapSizeToNext++;
                    if (rDataFeatures[j].properties.originalColor !== null) {
                        nextColor = rDataFeatures[j].properties.originalColor;
                        break;
                    }
                }

                const MAX_GAP_FILL = 20; // Maximum sub-segments to interpolate across empty spaces.

                // Parse rgb string to rgb array helper
                const parseRgb = (rgbStr) => {
                    const match = rgbStr.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/);
                    return match ? [parseInt(match[1]), parseInt(match[2]), parseInt(match[3])] : null;
                };

                // Only interpolate if we are close enough to known points
                if (gapSizeToPrev <= MAX_GAP_FILL && gapSizeToNext <= MAX_GAP_FILL && prevColor && nextColor) {
                    const pRGB = parseRgb(prevColor);
                    const nRGB = parseRgb(nextColor);
                    if (pRGB && nRGB) {
                        // Smoothly interpolate between prev and next based on relative position within gap
                        const totalGap = gapSizeToPrev + gapSizeToNext;
                        const ratio = gapSizeToPrev / totalGap;

                        const r = Math.round(pRGB[0] + (nRGB[0] - pRGB[0]) * ratio);
                        const g = Math.round(pRGB[1] + (nRGB[1] - pRGB[1]) * ratio);
                        rDataFeatures[i].properties.color = `rgb(${r}, ${g}, 0)`;
                    } else {
                        rDataFeatures[i].properties.color = prevColor;
                    }
                } else if (gapSizeToPrev <= MAX_GAP_FILL && prevColor) {
                    rDataFeatures[i].properties.color = prevColor;
                } else if (gapSizeToNext <= MAX_GAP_FILL && nextColor) {
                    rDataFeatures[i].properties.color = nextColor;
                } else {
                    rDataFeatures[i].properties.color = '#3b82f6'; // fallback Default blue if no markers exist nearby
                }
            }
        }

        return { type: 'FeatureCollection', features: rDataFeatures };

    }, [routeGeometry, pointsWithMeta.length, viewState.zoom, viewState.latitude, viewState.longitude]);


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
