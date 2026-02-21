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

    // Format Point Data for GeoJSON to render efficiently
    const pointData = useMemo(() => {
        return {
            type: 'FeatureCollection',
            features: points.map(p => {
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

                return {
                    type: 'Feature',
                    geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
                    properties: { color, heading: p.heading, speed: p.speed }
                };
            })
        };
    }, [points, sensitivity, speedInfluence]);

    // Route GeoJSON
    const routeData = useMemo(() => {
        if (!routeGeometry) return null;
        return {
            type: 'Feature',
            geometry: {
                type: 'LineString',
                coordinates: routeGeometry.map(coord => [coord[1], coord[0]]) // Leaflet uses [lat, lng], MapLibre uses [lng, lat]
            }
        };
    }, [routeGeometry]);


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

                {/* Draw Route */}
                {routeData && (
                    <Source id="route" type="geojson" data={routeData}>
                        <Layer
                            id="route-line"
                            type="line"
                            paint={{
                                'line-color': '#3b82f6',
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
                {points.filter(p => p.speed > 1 && p.heading !== undefined && p.heading !== null).map((p, idx) => {
                    let adjustedRoughness = p.roughness * sensitivity;
                    if (p.speed !== undefined && p.speed !== null) {
                        let speedFactor = (p.speed - 20) / (100 - 20);
                        if (speedFactor < 0) speedFactor = 0;
                        if (speedFactor > 1) speedFactor = 1;
                        adjustedRoughness = adjustedRoughness * (1 - (speedFactor * speedInfluence));
                    }
                    let color = '#ff0000';
                    if (adjustedRoughness < 2) color = '#00ff00';
                    else if (adjustedRoughness < 5) color = '#ffff00';
                    else if (adjustedRoughness < 8) color = '#ffa500';

                    return (
                        <Marker key={`dir-${idx}`} longitude={p.lng} latitude={p.lat} anchor="center">
                            <div style={{ transform: `rotate(${p.heading}deg)`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                <svg width="14" height="14" viewBox="0 0 24 24" fill={color} stroke="#000" strokeWidth="1">
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
                            {destination.name}
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
