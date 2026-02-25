import { useEffect, useRef, useState } from 'react';

export function useWakeLock(enabled) {
    const wakeLock = useRef(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        // Cleanup function
        const releaseLock = async () => {
            if (wakeLock.current) {
                try {
                    await wakeLock.current.release();
                    wakeLock.current = null;
                } catch (err) {
                    console.error('Wake Lock Release Error:', err);
                }
            }
        };

        if (!enabled) {
            releaseLock();
            return;
        }

        const requestWakeLock = async () => {
            try {
                if ('wakeLock' in navigator) {
                    wakeLock.current = await navigator.wakeLock.request('screen');
                    console.log('Wake Lock is active');
                }
            } catch (err) {
                console.error(`${err.name}, ${err.message}`);
                setError(err);
            }
        };

        requestWakeLock();

        // Re-acquire lock logic if visibility changes
        const handleVisibilityChange = async () => {
            if (document.visibilityState === 'visible' && enabled) {
                await requestWakeLock();
            }
        };

        document.addEventListener('visibilitychange', handleVisibilityChange);

        return () => {
            document.removeEventListener('visibilitychange', handleVisibilityChange);
            releaseLock();
        };
    }, [enabled]);

    return { error };
}
