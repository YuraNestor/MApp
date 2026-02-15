import { useState, useEffect, useRef } from 'react';
import './index.css';
import MapData from './components/MapData';
import NavigationOverlay from './components/NavigationOverlay';
import { useSensors } from './lib/sensors';

function App() {
  const [isRecording, setIsRecording] = useState(false);
  const [currentPos, setCurrentPos] = useState(null);
  const [points, setPoints] = useState([]);

  // Use our custom sensor hook
  const { roughness, motionData, requestPermission } = useSensors(isRecording);

  // Geo-location tracking
  useEffect(() => {
    let watchId;
    if ('geolocation' in navigator) {
      watchId = navigator.geolocation.watchPosition(
        (pos) => {
          const { latitude, longitude } = pos.coords;
          setCurrentPos({ lat: latitude, lng: longitude });
        },
        (err) => console.error("Geo error:", err),
        { enableHighAccuracy: true, timeout: 5000, maximumAge: 0 }
      );
    }
    return () => {
      if (watchId) navigator.geolocation.clearWatch(watchId);
    };
  }, []);

  // Refs for tracking latest values in interval
  const posRef = useRef(null);
  const roughnessRef = useRef(0);

  useEffect(() => {
    posRef.current = currentPos;
    roughnessRef.current = roughness;
  }, [currentPos, roughness]);

  // Record data points
  useEffect(() => {
    if (!isRecording) return;

    const interval = setInterval(() => {
      // Use refs to get latest values without resetting interval
      if (posRef.current) {
        setPoints(prev => [
          ...prev,
          {
            lat: posRef.current.lat,
            lng: posRef.current.lng,
            roughness: roughnessRef.current,
            timestamp: Date.now()
          }
        ]);
      }
    }, 1000); // 1 point per second

    return () => clearInterval(interval);
  }, [isRecording]); // Only restart if recording status changes

  return (
    <div style={{ width: '100vw', height: '100vh', position: 'relative' }}>
      <MapData points={points} currentPos={currentPos} />

      <NavigationOverlay
        isRecording={isRecording}
        onToggleRecording={async () => {
          if (!isRecording) {
            const granted = await requestPermission();
            if (granted) setIsRecording(true);
          } else {
            setIsRecording(false);
          }
        }}
        roughness={roughness}
      />

      {/* Debug view for desktop/testing */}
      <div style={{
        position: 'absolute',
        top: 10,
        right: 10,
        background: 'rgba(0,0,0,0.5)',
        color: 'white',
        padding: 10,
        fontSize: 10,
        pointerEvents: 'none',
        zIndex: 9999
      }}>
        <p>Lat: {currentPos?.lat.toFixed(4)}</p>
        <p>Lng: {currentPos?.lng.toFixed(4)}</p>
        <p>Roughness: {roughness.toFixed(2)}</p>
        <p>AccX: {motionData.x?.toFixed(2)}</p>
        <p>AccY: {motionData.y?.toFixed(2)}</p>
        <p>AccZ: {motionData.z?.toFixed(2)}</p>
      </div>
    </div>
  );
}

export default App;
