export const getColorFromRoughness = (roughness) => {
    const clampledRoughness = Math.max(0, Math.min(10, roughness));

    let r, g;
    if (clampledRoughness <= 5) {
        // 0 to 5: Green is 255, Red goes 0 -> 255
        g = 255;
        r = Math.round((clampledRoughness / 5) * 255);
    } else {
        // 5 to 10: Red is 255, Green goes 255 -> 0
        r = 255;
        g = Math.round((1 - ((clampledRoughness - 5) / 5)) * 255);
    }

    return `rgb(${r}, ${g}, 0)`;
};
