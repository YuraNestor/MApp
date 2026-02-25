import React, { useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Text, TouchableOpacity } from 'react-native';
import Mapbox from '@rnmapbox/maps';
import { getDistance, getColorFromRoughness, getPerpendicularDist } from '@mapp/shared';

// Initialize Mapbox with MapLibre backend (no token required for open styles, sk-placeholder is used in app.json)
Mapbox.setAccessToken('sk-placeholder');

export default function App() {
  const [routeGeometry, setRouteGeometry] = useState(null);
  const [points, setPoints] = useState([]);

  // Mock initial fetch or simulation data could go here...

  // MapData calculation using the shared workspace
  const routeData = useMemo(() => {
    if (!routeGeometry) return null;

    // We can use the same segment-splitting logic or Mapbox's native lineGradient.
    // For now, let's just pass the single line to leverage Mapbox!
    return {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          geometry: {
            type: 'LineString',
            coordinates: routeGeometry
          },
          properties: {}
        }
      ]
    };
  }, [routeGeometry]);

  return (
    <View style={styles.container}>
      <Mapbox.MapView style={styles.map} styleURL="https://tiles.stadiamaps.com/styles/alidade_smooth_dark.json">
        <Mapbox.Camera
          zoomLevel={14}
          centerCoordinate={[30.5234, 50.4501]} // Kyiv
          pitch={60}
          heading={0}
        />

        {routeData && (
          <Mapbox.ShapeSource id="route-source" shape={routeData} lineMetrics>
            <Mapbox.LineLayer
              id="route-layer"
              style={{
                lineWidth: 8,
                lineCap: 'round',
                lineJoin: 'round',
                // Example of native line-gradient! 
                // In reality, this array will be generated dynamically using points projection.
                lineGradient: [
                  'interpolate',
                  ['linear'],
                  ['line-progress'],
                  0, 'green',
                  0.5, 'yellow',
                  1, 'red',
                ],
              }}
            />
          </Mapbox.ShapeSource>
        )}
      </Mapbox.MapView>

      <View style={styles.overlay}>
        <Text style={styles.title}>MApp Native</Text>
        <Text style={styles.subtitle}>MapLibre GPU UI</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  map: {
    flex: 1,
  },
  overlay: {
    position: 'absolute',
    top: 50,
    left: 20,
    backgroundColor: 'rgba(0,0,0,0.7)',
    padding: 15,
    borderRadius: 10,
  },
  title: {
    color: 'white',
    fontSize: 20,
    fontWeight: 'bold',
  },
  subtitle: {
    color: '#aaa',
    fontSize: 14,
  }
});
