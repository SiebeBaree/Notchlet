"use client";

import { useSyncExternalStore } from "react";

const query = "(prefers-reduced-motion: reduce)";

function subscribe(onChange: () => void) {
    const media = window.matchMedia(query);
    media.addEventListener("change", onChange);
    return () => media.removeEventListener("change", onChange);
}

function snapshot() {
    return window.matchMedia(query).matches;
}

// Match the server render before applying the browser's motion preference.
function serverSnapshot() {
    return false;
}

export function useReducedMotion() {
    return useSyncExternalStore(subscribe, snapshot, serverSnapshot);
}
