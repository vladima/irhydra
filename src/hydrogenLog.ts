import { LoadHydrogenLog } from "./protocol";
import * as fs from "fs";
import * as es from "event-stream";

export default class HydrogenLog {
    private lines: string[];
    private methods: LoadHydrogenLog.Method[];
    public load(path: string, cb: (methods: LoadHydrogenLog.Method[]) => void): void {
        this.lines = [];
        this.methods = [];

        fs.createReadStream(path)
            .pipe(es.split(/\n/))
            .pipe(es.mapSync((line) => {
                this.lines.push(line);
            }))
            .on("end", () => {
                cb(this.methods)
            });
    }
}