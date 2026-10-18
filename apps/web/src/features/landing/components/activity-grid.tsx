const levels = ["#252529", "#163c65", "#205d9b", "#348bdd", "#92c3f5"];

// Fixed sample data keeps these server-rendered illustrations identical across requests.
let seed = 7;
const activity = Array.from({ length: 53 * 7 }, (_, day) => {
    seed = (seed * 16807) % 2147483647;
    const value = seed % 127;
    return { day: `day-${day}`, color: levels[value < 52 ? 0 : (value % 4) + 1] };
});

export function ActivityGrid() {
    return (
        <div aria-hidden className="grid grid-flow-col grid-cols-[repeat(53,minmax(0,1fr))] grid-rows-7 gap-[2px]">
            {activity.map(({ color, day }) => (
                <span key={day} className="aspect-square rounded-[1px]" style={{ background: color }} />
            ))}
        </div>
    );
}
