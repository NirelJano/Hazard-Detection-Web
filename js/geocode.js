האה// ============================================
// Reverse Geocoding (Mapbox Geocoding API v5)
// ============================================

/**
 * Convert latitude/longitude to a human-readable address string.
 * Uses Mapbox Geocoding API v5.
 *
 * @param {number} lat  – Latitude  (WGS84)
 * @param {number} lng  – Longitude (WGS84)
 * @returns {Promise<string>} Resolved address (e.g. "אינשטיין 21, חיפה")
 * @throws {Error} If the API call fails or returns no results
 */
export async function reverseGeocode(lat, lng) {
    const token = window.ENV?.MAPBOX_ACCESS_TOKEN;
    if (!token) {
        throw new Error('MAPBOX_ACCESS_TOKEN is not configured in .env');
    }

    const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${lng},${lat}.json`
        + `?access_token=${token}`
        + `&language=he`          // Prefer Hebrew results
        + `&types=address,place`  // Prefer street-level, fall back to city/town
        + `&limit=1`;

    const res = await fetch(url);

    if (!res.ok) {
        throw new Error(`Geocoding request failed (HTTP ${res.status})`);
    }

    const data = await res.json();

    if (!data.features || data.features.length === 0) {
        throw new Error('No address found for the given coordinates');
    }

    // Build a concise address without the country name.
    // Mapbox returns context entries like [{ id: "place.xxx", text: "חיפה" }, ...]
    const feature = data.features[0];

    // "text" is the street name (+ house number if available via "address" prop)
    let street = feature.text || '';
    if (feature.address) {
        street = `${street} ${feature.address}`;
    }

    // Extract city/place from context
    const placeCtx = (feature.context || []).find(c => c.id.startsWith('place'));
    const city = placeCtx?.text || '';

    // Combine: "אינשטיין 21, חיפה"
    const parts = [street, city].filter(Boolean);
    if (parts.length === 0) {
        throw new Error('No meaningful address found for the given coordinates');
    }

    return parts.join(', ');
}
