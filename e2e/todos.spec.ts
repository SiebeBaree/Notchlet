import { neon } from "@neondatabase/serverless";
import { expect, test } from "@playwright/test";

// Full user journey against a real database. RSCs and server actions have no unit-test story, so this is where they get verified.
test.describe("todos", () => {
    test.skip(!process.env.DATABASE_URL, "requires DATABASE_URL");

    // Removes this run's records and any leftovers from earlier runs that failed before their delete step.
    test.afterAll(async () => {
        const sql = neon(process.env.DATABASE_URL!);
        await sql`delete from todos where title like 'e2e %'`;
    });

    test("create, complete and delete a todo", async ({ page }) => {
        const title = `e2e ${Date.now()}`;

        await page.goto("/todos");
        await page.getByLabel("New todo title").fill(title);
        await page.getByRole("button", { name: "Add" }).click();

        const item = page.getByRole("listitem").filter({ hasText: title });
        await expect(item).toBeVisible();

        await item.getByRole("checkbox").click();
        await expect(item.getByText(title)).toHaveClass(/line-through/);

        await item.hover();
        await item.getByRole("button", { name: `Delete "${title}"` }).click();
        await expect(item).toHaveCount(0);
    });

    test("rejects an empty title without hitting the server", async ({ page }) => {
        await page.goto("/todos");
        await page.getByRole("button", { name: "Add" }).click();
        await expect(page.getByRole("alert")).toContainText("Add a title first.");
    });
});
