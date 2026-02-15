import { Play, Square, Hammer } from 'lucide-react';

export default function NavigationOverlay({ isRecording, onToggleRecording, roughness }) {

    // Convert 0-10 scale to percentage for a bar
    const qualityPercent = Math.min(Math.max(roughness * 10, 0), 100);

    let statusColor = 'bg-green-500';
    if (roughness > 3) statusColor = 'bg-yellow-500';
    if (roughness > 6) statusColor = 'bg-red-500';

    return (
        <div style={{
            position: 'absolute',
            bottom: 'calc(20px + env(safe-area-inset-bottom))', // Respect iPhone home indicator/toolbar
            left: '50%',
            transform: 'translateX(-50%)',
            zIndex: 1000,
            display: 'flex',
            flexDirection: 'column',
            gap: '10px',
            alignItems: 'center',
            width: '90%',
            maxWidth: '400px'
        }}>

            {/* Quality Meter */}
            <div style={{
                background: 'rgba(30, 30, 30, 0.9)',
                padding: '15px',
                borderRadius: '12px',
                width: '100%',
                backdropFilter: 'blur(10px)',
                border: '1px solid rgba(255,255,255,0.1)'
            }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', color: '#fff', fontSize: '0.9rem' }}>
                    <span>Road Roughness</span>
                    <span>{roughness.toFixed(1)} / 10</span>
                </div>
                <div style={{ height: '8px', background: '#333', borderRadius: '4px', overflow: 'hidden' }}>
                    <div style={{
                        width: `${qualityPercent}%`,
                        height: '100%',
                        background: roughness > 6 ? '#ef4444' : roughness > 3 ? '#eab308' : '#22c55e',
                        transition: 'width 0.3s ease, background 0.3s ease'
                    }} />
                </div>
            </div>

            {/* Controls */}
            <button
                onClick={onToggleRecording}
                style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '12px',
                    padding: '16px 32px',
                    borderRadius: '50px',
                    border: 'none',
                    background: isRecording ? '#ef4444' : '#22c55e',
                    color: 'white',
                    fontSize: '1.2rem',
                    fontWeight: '600',
                    boxShadow: '0 4px 15px rgba(0,0,0,0.3)',
                    cursor: 'pointer',
                    transition: 'transform 0.2s active'
                }}
                onMouseDown={(e) => e.target.style.transform = 'scale(0.95)'}
                onMouseUp={(e) => e.target.style.transform = 'scale(1)'}
            >
                {isRecording ? <Square size={24} fill="currentColor" /> : <Play size={24} fill="currentColor" />}
                {isRecording ? 'Stop Recording' : 'Start Recording'}
            </button>

            {/* Debug Info (Optional) */}
            {/* <div style={{ fontSize: '10px', color: '#aaa' }}>
        Press <Hammer size={10} /> to Simulate Bump
      </div> */}
        </div>
    );
}
