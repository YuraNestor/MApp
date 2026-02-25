export const getPerpendicularDist = (p, start, end) => {
    const R = 6371000;
    const d2r = Math.PI / 180;

    // start is [lng, lat], end is [lng, lat]
    const lat1 = start[1] * d2r;
    const lng1 = start[0] * d2r;
    const lat2 = end[1] * d2r;
    const lng2 = end[0] * d2r;
    const lat3 = p.lat * d2r;
    const lng3 = p.lng * d2r;

    const cosLat = Math.cos((lat1 + lat2) / 2);

    const x2 = (lng2 - lng1) * cosLat;
    const y2 = lat2 - lat1;
    const x3 = (lng3 - lng1) * cosLat;
    const y3 = lat3 - lat1;

    const l2 = x2 * x2 + y2 * y2;
    if (l2 === 0) return Infinity; // Start and end are identical

    const t = (x3 * x2 + y3 * y2) / l2;

    if (t < 0 || t > 1) return Infinity; // Perpendicular does not hit the segment

    const projX = t * x2;
    const projY = t * y2;

    const dx = x3 - projX;
    const dy = y3 - projY;

    return Math.sqrt(dx * dx + dy * dy) * R;
};

export const getDistance = (lat1, lon1, lat2, lon2) => {
    const R = 6371e3; // metres
    const φ1 = lat1 * Math.PI / 180;
    const φ2 = lat2 * Math.PI / 180;
    const Δφ = (lat2 - lat1) * Math.PI / 180;
    const Δλ = (lon2 - lon1) * Math.PI / 180;

    const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
        Math.cos(φ1) * Math.cos(φ2) *
        Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c;
};
