.pragma library

// Which icon the bar's CPU & RAM pill and its popup show for each figure
// (modules/sekai/bar/ResourceIndicator.qml, ResourcePopup.qml). No QML here, so
// tests/resource-test can run it under node.
//
// CPU is the chip ("memory" is Material's name for it, and the chip is what a
// processor looks like), always the same. RAM is the pie that fills up as the
// memory does: "how full" is the question a filling pie answers. The two were the
// other way round, and the bar has no CPU / RAM words beside them, so a busy CPU
// read as full memory (issue #168; docs/RESOURCE-ICONS.md).
var CPU = "memory";

// Material Symbols Rounded ships the "clock_loader" pie in these six steps
// only, so the percent snaps to the closest one (midpoints 15/30/50/70/85)
// rather than an even split like the battery's frame_1..frame_6.
function pie(pct) {
    var p = Number(pct) || 0;
    if (p < 15) return "clock_loader_10";
    if (p < 30) return "clock_loader_20";
    if (p < 50) return "clock_loader_40";
    if (p < 70) return "clock_loader_60";
    if (p < 85) return "clock_loader_80";
    return "clock_loader_90";
}

function cpu() { return CPU; }
function ram(pct) { return pie(pct); }
