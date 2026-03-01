import { useState } from 'react';
import { Search, X, MapPin } from 'lucide-react';

export default function SearchModal({ isOpen, onClose, onSelect }) {
    const [query, setQuery] = useState('');
    const [results, setResults] = useState([]);
    const [isSearching, setIsSearching] = useState(false);

    if (!isOpen) return null;

    const handleSearch = async (e) => {
        e.preventDefault();
        if (!query.trim()) return;

        setIsSearching(true);
        try {
            // Using OSM Nominatim API
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&limit=5`
            );
            const data = await response.json();
            setResults(data);
        } catch (error) {
            console.error("Search error:", error);
            alert("Failed to search. Please check your connection.");
        } finally {
            setIsSearching(false);
        }
    };

    return (
        <div style={{
            position: 'fixed',
            top: 0, left: 0, right: 0, bottom: 0,
            background: 'rgba(0,0,0,0.8)',
            zIndex: 2000,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            paddingTop: 'calc(60px + env(safe-area-inset-top))',
            paddingLeft: '20px',
            paddingRight: '20px'
        }}>
            <div style={{
                width: '100%',
                maxWidth: '500px',
                background: '#2a2a2a',
                borderRadius: '16px',
                overflow: 'hidden',
                boxShadow: '0 10px 30px rgba(0,0,0,0.5)',
                display: 'flex',
                flexDirection: 'column',
                maxHeight: '80vh'
            }}>
                {/* Header */}
                <div style={{
                    display: 'flex',
                    alignItems: 'center',
                    padding: '16px',
                    borderBottom: '1px solid rgba(255,255,255,0.1)'
                }}>
                    <form onSubmit={handleSearch} style={{ flex: 1, display: 'flex', alignItems: 'center' }}>
                        <Search size={20} color="#888" style={{ marginRight: '10px' }} />
                        <input
                            autoFocus
                            type="text"
                            placeholder="Search destination..."
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            style={{
                                flex: 1,
                                background: 'transparent',
                                border: 'none',
                                color: 'white',
                                fontSize: '16px',
                                outline: 'none'
                            }}
                        />
                    </form>
                    <button
                        onClick={onClose}
                        style={{
                            background: 'none',
                            border: 'none',
                            color: '#888',
                            cursor: 'pointer',
                            padding: '4px'
                        }}
                    >
                        <X size={24} />
                    </button>
                </div>

                {/* Results Container */}
                <div style={{
                    overflowY: 'auto',
                    flex: 1
                }}>
                    {isSearching ? (
                        <div style={{ padding: '20px', textAlign: 'center', color: '#888' }}>
                            Searching...
                        </div>
                    ) : results.length > 0 ? (
                        results.map((res, index) => (
                            <div
                                key={index}
                                onClick={() => {
                                    onSelect({
                                        lat: parseFloat(res.lat),
                                        lng: parseFloat(res.lon),
                                        name: res.display_name
                                    });
                                }}
                                style={{
                                    padding: '16px',
                                    borderBottom: '1px solid rgba(255,255,255,0.05)',
                                    display: 'flex',
                                    alignItems: 'flex-start',
                                    cursor: 'pointer',
                                    color: 'white'
                                }}
                            >
                                <MapPin size={20} color="#3b82f6" style={{ marginRight: '12px', marginTop: '2px', flexShrink: 0 }} />
                                <div style={{ fontSize: '14px', lineHeight: '1.4' }}>
                                    {res.display_name}
                                </div>
                            </div>
                        ))
                    ) : query.length > 0 && !isSearching ? (
                        <div style={{ padding: '20px', textAlign: 'center', color: '#888' }}>
                            No results found.
                        </div>
                    ) : (
                        <div style={{ padding: '20px', textAlign: 'center', color: '#888' }}>
                            Type an address or place name to search.
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
