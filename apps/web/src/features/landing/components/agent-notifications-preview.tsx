const notifications = [
    { label: "Turn finished", color: "#3d9cff" },
    { label: "Needs your input", color: "#e5ac40" },
];

export function AgentNotificationsPreview() {
    return (
        <div className="w-full max-w-[250px] space-y-3">
            {notifications.map(({ label, color }) => (
                <div key={label} className="text-center">
                    <div className="flex h-10 justify-center overflow-hidden rounded-t-md bg-linear-to-br from-[#384368] to-[#141726]">
                        <div
                            style={{ borderColor: color }}
                            className="h-6 w-24 rounded-b-xl border-2 border-t-0 bg-black"
                        />
                    </div>
                    <p className="mt-1 text-[10px] text-ink-3">{label}</p>
                </div>
            ))}
        </div>
    );
}
