import Image from "next/image";

import wallpaper from "../tahoe-dark.webp";
import { HeroCopy } from "./hero-copy";
import { Notch } from "./notch";

// The Mac screen: wallpaper, notch and launch copy. DeviceScroll decides how big the screen is.
export function Hero() {
    return (
        <div className="relative h-full overflow-hidden">
            <Image src={wallpaper} alt="" fill priority placeholder="blur" sizes="100vw" className="object-cover" />
            <Notch />
            <HeroCopy />
        </div>
    );
}
