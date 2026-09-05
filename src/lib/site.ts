import "server-only";
import { env } from "@/lib/env/server";

export const siteName = "Notchlet";
export const siteTitle = "Notchlet, Claude Code and Codex usage in your Mac notch";
export const siteDescription =
    "See how much of your Claude Code, Codex, Cursor and OpenCode plan is left without leaving your editor. Free and open source, for macOS.";
export const siteUrl = new URL(env.APP_URL ?? "http://localhost:3000");
