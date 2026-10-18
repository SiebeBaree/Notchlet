import { NextResponse } from "next/server";

import { latestDownloadUrl } from "@/features/landing";

// Every Download button points here, and so does anyone who types /download. GitHub serves the asset as an
// attachment, so the redirect downloads the app and leaves the visitor on the page they came from.
export async function GET() {
    return NextResponse.redirect(await latestDownloadUrl());
}
