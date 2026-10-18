import "server-only";
import { env } from "@/lib/env/server";

export const siteName = "Notchlet";
export const siteTitle = "Notchlet, Claude Code and Codex usage in your Mac notch";
export const siteDescription =
    "Track Claude Code, Codex, Cursor and OpenCode usage, reset times and history from your Mac's notch. Free and open source. macOS 14 or later.";
export const siteUrl = new URL(env.APP_URL ?? "http://localhost:3000");
