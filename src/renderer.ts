import { ipcRenderer } from "electron";
import { LoadHydrogenLog } from "./protocol";
import HydrogenLog from "./hydrogenLog";
import * as fs from "fs";
import * as path from "path";

const log = new HydrogenLog();

// invoked from the dart
function load(file: {path: string}, cb: (arg: any) => void) {
    if (path.extname(file.path) === ".cfg") {
        console.log(`load hydrogen log '${file.path}'`)
        loadHydrogenLog(file.path, cb);
    }
    else {
        console.log(`load code '${file.path}'`)
        loadCode(file.path, cb);
    }
}

function getText(startLine: number, endLine: number): string {
    return log.getPhaseBodyText(startLine, endLine);
}

// pre-parse hydrogen log, return list of method descriptors through the callback
function loadHydrogenLog(path: string, cb: (methods: any) => void) {
    log.load(path, x => {
        cb({data: x, text: require("fs").readFileSync(path).toString()})
    });
    if (1) return;
    ipcRenderer.once(LoadHydrogenLog.ResponseChannel, (e, response: LoadHydrogenLog.Response) => {
        cb(response.methods);
    });
    const request: LoadHydrogenLog.Request = { path }
    ipcRenderer.send(LoadHydrogenLog.RequestChannel, request )
}

function loadCode(path: string, cb: (code: any) => void) {
    fs.readFile(path, (err, data) => {
        const text = data.toString();
        cb({data: text});
    })
}