import { X, Download, Upload } from 'lucide-react';

export default function SettingsModal({
    isOpen,
    onClose,
    currentStyle,
    onStyleChange,
    sensitivity,
    onSensitivityChange,
    onExport,
    onImport
}) {
    if (!isOpen) return null;

    const mapStyles = [
        { id: 'dark', name: 'Dark Mode (CartoDB)' },
        { id: 'light', name: 'Light Mode (OSM)' },
        { id: 'satellite', name: 'Satellite (Esri)' },
    ];

    return (
        <div style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: '100%',
            height: '100%',
            backgroundColor: 'rgba(0,0,0,0.7)',
            zIndex: 2000,
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
            backdropFilter: 'blur(5px)'
        }}>
            <div style={{
                backgroundColor: '#242424',
                padding: '2rem',
                borderRadius: '16px',
                width: '90%',
                maxWidth: '400px',
                color: 'white',
                boxShadow: '0 10px 25px rgba(0,0,0,0.5)',
                position: 'relative'
            }}>
                <button
                    onClick={onClose}
                    style={{
                        position: 'absolute',
                        top: '1rem',
                        right: '1rem',
                        background: 'none',
                        border: 'none',
                        color: '#aaa',
                        cursor: 'pointer'
                    }}
                >
                    <X size={24} />
                </button>

                <h2 style={{ marginTop: 0, marginBottom: '1.5rem' }}>Settings</h2>

                <div style={{ marginBottom: '2rem' }}>
                    <h3 style={{ fontSize: '1rem', marginBottom: '0.5rem', color: '#aaa' }}>Map Style</h3>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                        {mapStyles.map(style => (
                            <label k={style.id} style={{ display: 'flex', alignItems: 'center', gap: '10px', cursor: 'pointer' }}>
                                <input
                                    type="radio"
                                    name="mapStyle"
                                    value={style.id}
                                    checked={currentStyle === style.id}
                                    onChange={() => onStyleChange(style.id)}
                                    style={{ accentColor: '#646cff' }}
                                />
                                {style.name}
                            </label>
                        ))}
                    </div>
                </div>

                <div style={{ marginBottom: '2rem' }}>
                    <h3 style={{ fontSize: '1rem', marginBottom: '0.5rem', color: '#aaa' }}>
                        Sensitivity: {sensitivity}x
                    </h3>
                    <input
                        type="range"
                        min="0.5"
                        max="3.0"
                        step="0.1"
                        value={sensitivity}
                        onChange={(e) => onSensitivityChange(parseFloat(e.target.value))}
                        style={{ width: '100%', accentColor: '#646cff', cursor: 'pointer' }}
                    />
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: '#666' }}>
                        <span>Less Sensitive</span>
                        <span>More Sensitive</span>
                    </div>
                </div>

                <div>
                    <h3 style={{ fontSize: '1rem', marginBottom: '1rem', color: '#aaa' }}>Data Management</h3>
                    <div style={{ display: 'flex', gap: '1rem' }}>
                        <button
                            onClick={onExport}
                            style={{
                                display: 'flex',
                                alignItems: 'center',
                                gap: '8px',
                                padding: '10px 16px',
                                borderRadius: '8px',
                                border: '1px solid #444',
                                background: '#333',
                                color: 'white',
                                cursor: 'pointer',
                                flex: 1,
                                justifyContent: 'center'
                            }}
                        >
                            <Download size={18} /> Export CSV
                        </button>

                        <label style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: '8px',
                            padding: '10px 16px',
                            borderRadius: '8px',
                            border: '1px solid #444',
                            background: '#333',
                            color: 'white',
                            cursor: 'pointer',
                            flex: 1,
                            justifyContent: 'center'
                        }}>
                            <Upload size={18} /> Import CSV
                            <input
                                type="file"
                                accept=".csv"
                                style={{ display: 'none' }}
                                onChange={onImport}
                            />
                        </label>
                    </div>
                </div>
            </div>
        </div>
    );
}
