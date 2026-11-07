// Loads modules/common/functions/PresetParts.js (a QML `.pragma library` file) into
// node, so the tests run the same code the shell does.
const fs = require("fs")
const src = fs.readFileSync(require("./locate")("modules/common/functions/PresetParts.js"), "utf8").replace(".pragma library", "")
const names = ["isObj", "snapshotPart", "partNow", "capture", "mergeRestore", "wear", "digestPart", "stubPart", "digestWidgets", "fillBefore", "readPart", "problems", "withBarOff", "barNoModules"]
module.exports = new Function("console", src + ";return {" + names.map(n => n + ":" + n).join(",") + "}")(console)
