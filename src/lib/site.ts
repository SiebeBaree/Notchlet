import "server-only";
import { env } from "@/lib/env/server";

export const siteName = "Todos";
export const siteDescription = "A Next.js starter with the full production toolchain wired up.";
export const siteUrl = new URL(env.APP_URL ?? "http://localhost:3000");
