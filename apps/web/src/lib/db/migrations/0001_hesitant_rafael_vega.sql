CREATE TABLE "signups" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "signups_email_unique" UNIQUE("email")
);
--> statement-breakpoint
DROP TABLE "todos" CASCADE;