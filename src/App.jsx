import { useState, useEffect, useRef } from 'react';
import './index.css';
import MapData from './components/MapData';
import NavigationOverlay from './components/NavigationOverlay';
import SettingsModal from './components/SettingsModal';
import { Settings, Crosshair } from 'lucide-react';
import { useSensors } from './lib/sensors';
import { useWakeLock } from './lib/wakeLock';
import pkg from '../package.json';

function App() {
  const [isRecording, setIsRecording] = useState(false);
  const [currentPos, setCurrentPos] = useState(null);
  const [points, setPoints] = useState([]);

  // Use our custom sensor hook
  const { roughness, motionData, requestPermission } = useSensors(isRecording);

  // Prevent screen sleep while recording
  useWakeLock(isRecording);

  // Geo-location tracking
  useEffect(() => {
    let watchId;
    if ('geolocation' in navigator) {
      watchId = navigator.geolocation.watchPosition(
        (pos) => {
          const { latitude, longitude, speed, heading } = pos.coords;
          // Speed is in m/s. Convert to km/h. If null, use 0.
          // Heading is in degrees (0-360). 0 is North. NaN/null if speed is 0.
          const speedKmh = speed ? speed * 3.6 : 0;
          const currentHeading = heading || 0;
          setCurrentPos({ lat: latitude, lng: longitude, speed: speedKmh, heading: currentHeading });
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

  // Settings State
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [mapStyle, setMapStyle] = useState('dark');
  const [followUser, setFollowUser] = useState(true);
  const [sensitivity, setSensitivity] = useState(1.0);
  const [speedInfluence, setSpeedInfluence] = useState(0.5); // 0 to 1

  // CSV Export
  const handleExport = () => {
    const headers = "timestamp,lat,lng,roughness,speed,heading\n";
    const csvContent = points.map(p =>
      `${new Date(p.timestamp).toISOString()},${p.lat},${p.lng},${p.roughness},${p.speed || ''},${p.heading || ''}`
    ).join("\n");

    const blob = new Blob([headers + csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `road_quality_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // CSV Import
  const handleImport = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (evt) => {
      const text = evt.target.result;
      const lines = text.split('\n').slice(1); // Skip header
      const newPoints = lines
        .filter(line => line.trim() !== '')
        .map(line => {
          const [timestamp, lat, lng, roughness, speed, heading] = line.split(',');
          return {
            timestamp: new Date(timestamp).getTime(),
            lat: parseFloat(lat),
            lng: parseFloat(lng),
            roughness: parseFloat(roughness),
            speed: speed ? parseFloat(speed) : undefined,
            heading: heading ? parseFloat(heading) : undefined
          };
        })
        .filter(p => !isNaN(p.lat) && !isNaN(p.lng));

      setPoints(prev => [...prev, ...newPoints]);
      setIsSettingsOpen(false);
      alert(`Imported ${newPoints.length} points.`);
    };
    reader.readAsText(file);
  };

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
            speed: posRef.current.speed,
            heading: posRef.current.heading,
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

      {/* Version Display */}
      <div style={{
        position: 'absolute',
        top: 'calc(10px + env(safe-area-inset-top))',
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 1002,
        background: 'rgba(0,0,0,0.5)',
        color: 'rgba(255,255,255,0.7)',
        padding: '2px 8px',
        borderRadius: '10px',
        fontSize: '10px',
        pointerEvents: 'none'
      }}>
        v{pkg.version}
      </div>

      <MapData
        points={points}
        currentPos={currentPos}
        mapStyle={mapStyle}
        followUser={followUser}
        onMapDrag={() => setFollowUser(false)}
        sensitivity={sensitivity}
        speedInfluence={speedInfluence}
      />

      {/* Settings Button (Top Right) */}
      <button
        onClick={() => setIsSettingsOpen(true)}
        style={{
          position: 'absolute',
          top: 'calc(20px + env(safe-area-inset-top))', // Respect iPhone status bar
          right: '20px',
          zIndex: 1001,
          background: 'rgba(30,30,30,0.8)',
          color: 'white',
          border: '1px solid rgba(255,255,255,0.2)',
          borderRadius: '50%',
          width: '44px',
          height: '44px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          backdropFilter: 'blur(5px)',
          cursor: 'pointer'
        }}
      >
        <Settings size={24} />
      </button>

      <SettingsModal
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        currentStyle={mapStyle}
        onStyleChange={setMapStyle}
        sensitivity={sensitivity}
        onSensitivityChange={setSensitivity}
        speedInfluence={speedInfluence}
        onSpeedInfluenceChange={setSpeedInfluence}
        onExport={handleExport}
        onImport={handleImport}
      />

      {/* Recenter Button */}
      {!followUser && (
        <button
          onClick={() => setFollowUser(true)}
          style={{
            position: 'absolute',
            bottom: 'calc(240px + env(safe-area-inset-bottom))', // Moved higher to avoid overlap
            right: '20px',
            zIndex: 1001,
            background: 'rgba(30,30,30,0.8)',
            color: 'white',
            border: '1px solid rgba(255,255,255,0.2)',
            borderRadius: '50%',
            width: '44px',
            height: '44px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            backdropFilter: 'blur(5px)',
            cursor: 'pointer'
          }}
        >
          <Crosshair size={24} />
        </button>
      )}

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


    </div>
  );
}

export default App;
