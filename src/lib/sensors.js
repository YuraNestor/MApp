import { useState, useEffect, useRef } from 'react';

export function useSensors(isRecording) {
    const [roughness, setRoughness] = useState(0);
    const [motionData, setMotionData] = useState({ x: 0, y: 0, z: 0 });
    const lastUpdate = useRef(Date.now());
    const processingWindow = useRef([]);

    useEffect(() => {
        if (!isRecording) {
            setRoughness(0);
            return;
        }

        const handleMotion = (event) => {
            const { x, y, z } = event.accelerationIncludingGravity || { x: 0, y: 0, z: 0 };

            // Simple roughness calculation: variance of the Z-axis (vertical) acceleration
            // ideally we'd remove gravity and smooth it out, but for raw roughness:
            // We look at the delta from 9.8 (approx gravity) or just the high-freq noise.

            setMotionData({ x, y, z });

            const now = Date.now();
            // Add magnitude of acceleration vector (ignoring direction)
            // Or just Z if phone is flat. Let's use magnitude to be orientation-independent-ish.
            const magnitude = Math.sqrt(x * x + y * y + z * z);

            // Store deviation from 1G (approx 9.8 m/s^2)
            const deviation = Math.abs(magnitude - 9.8);

            processingWindow.current.push(deviation);

            // Process every 500ms
            if (now - lastUpdate.current > 500) {
                const avgDeviation = processingWindow.current.reduce((a, b) => a + b, 0) / processingWindow.current.length;

                // Normalize: 0 to 10 scale.
                // Walking/driving smooth: deviation < 1. 
                // Pothole: deviation > 3-5.
                // Let's cap at 5 for max roughness.
                const score = Math.min((avgDeviation / 5) * 10, 10);

                setRoughness(score);
                processingWindow.current = [];
                lastUpdate.current = now;
            }
        };

        window.addEventListener('devicemotion', handleMotion);
        return () => window.removeEventListener('devicemotion', handleMotion);
    }, [isRecording]);

    const requestPermission = async () => {
        if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
            try {
                const permissionState = await DeviceMotionEvent.requestPermission();
                if (permissionState === 'granted') {
                    return true;
                } else {
                    alert("Permission to access motion sensors was denied.");
                    return false;
                }
            } catch (error) {
                console.error(error);
                return false;
            }
        }
        return true; // Non-iOS devices don't need permission
    };

    return { roughness, motionData, requestPermission };
}
