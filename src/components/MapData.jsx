import { MapContainer, TileLayer, CircleMarker, Popup, useMap, useMapEvents } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { useEffect, useState } from 'react';

// Helper to handle map events and centering
function MapController({ center, followUser, onMapDrag }) {
    const map = useMap();

    useMapEvents({
        dragstart: () => {
            onMapDrag();
        }
    });

    useEffect(() => {
        if (followUser && center) {
            map.setView(center);
        }
    }, [center, followUser, map]);

    return null;
}

// Map style URLs
const TILE_LAYERS = {
    dark: {
        url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
        attr: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
    },
    light: {
        url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
        attr: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    },
    satellite: {
        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        attr: 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
    }
};

export default function MapData({ points, currentPos, mapStyle = 'dark', followUser, onMapDrag, sensitivity = 1.0, speedInfluence = 0.5 }) {
    const [position, setPosition] = useState([51.505, -0.09]); // Default London
    const activeLayer = TILE_LAYERS[mapStyle] || TILE_LAYERS.dark;

    useEffect(() => {
        if (currentPos) {
            setPosition([currentPos.lat, currentPos.lng]);
        }
    }, [currentPos]);

    // Color gradient based on roughness (0-10), sensitivity, and speed
    const getColor = (point) => {
        let adjustedRoughness = point.roughness * sensitivity;

        // Speed Adjustment Logic
        // If we have speed data, we adjust.
        // 100 km/h = ideal (factor 1). 20 km/h = worst (factor 0).
        if (point.speed !== undefined && point.speed !== null) {
            const speed = point.speed;
            const minSpeed = 20;
            const maxSpeed = 100;

            // Normalize speed to 0-1 range (clamped)
            let speedFactor = (speed - minSpeed) / (maxSpeed - minSpeed);
            if (speedFactor < 0) speedFactor = 0;
            if (speedFactor > 1) speedFactor = 1;

            // Reduce roughness if speed is high.
            // Formula: NewRoughness = OldRoughness * (1 - (SpeedFactor * Influence))
            adjustedRoughness = adjustedRoughness * (1 - (speedFactor * speedInfluence));
        }

        if (adjustedRoughness < 2) return '#00ff00'; // Green
        if (adjustedRoughness < 5) return '#ffff00'; // Yellow
        if (adjustedRoughness < 8) return '#ffa500'; // Orange
        return '#ff0000'; // Red
    };

    return (
        <MapContainer center={position} zoom={15} style={{ height: '100%', width: '100%' }}>
            <TileLayer
                attribution={activeLayer.attr}
                url={activeLayer.url}
            />

            {currentPos && <MapController
                center={[currentPos.lat, currentPos.lng]}
                followUser={followUser}
                onMapDrag={onMapDrag}
            />}

            {/* Current Position Marker */}
            {currentPos && (
                <CircleMarker
                    center={[currentPos.lat, currentPos.lng]}
                    radius={10}
                    pathOptions={{ color: 'blue', fillColor: 'blue', fillOpacity: 0.5 }}
                >
                    <Popup>You are here</Popup>
                </CircleMarker>
            )}

            {/* Recorded Road Quality Points */}
            {points.map((p, idx) => (
                <CircleMarker
                    key={idx}
                    center={[p.lat, p.lng]}
                    radius={5}
                    pathOptions={{
                        color: getColor(p),
                        fillColor: getColor(p),
                        fillOpacity: 0.7,
                        stroke: false
                    }}
                />
            ))}
        </MapContainer>
    );
}
