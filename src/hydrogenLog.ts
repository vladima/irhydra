import { LoadHydrogenLog } from "./protocol";
import * as fs from "fs";
import * as es from "event-stream";

const enum Missing { Value = -1 }

export default class HydrogenLog {
    private lines: string[];
    private methods: LoadHydrogenLog.Method[];
    public load(path: string, cb: (methods: LoadHydrogenLog.Method[]) => void): void {
        this.lines = [];
        this.methods = [];

        // Matches tags that start/end compilation and cfg records.
        // final tagRe = new RegExp(r"(begin|end)_(compilation|cfg)\n");
        // Matches line containing method name and optimization id.
        // final compilationRe = new RegExp(r'name "([^"]*)"\n\s+method "[^"]*(:\d+)?"');
        // Matches line containing the name field.
        // final nameRe = new RegExp(r'name "([^"]*)"');
        const tagRe = /(begin|end)_(compilation|cfg)/;
        const compilationRe = /name "([^"]*)"\n\s+method "[^"]*(:\d+)?"/;
        const nameRe = /name "([^"]*)"/;

        let startLine = Missing.Value;
        fs.createReadStream(path)
            .pipe(es.split(/\n/))
            .pipe(es.mapSync((line) => {
                const n = this.lines.length;
                this.lines.push(line);

                const m = tagRe.exec(line);
                if (m) {
                    const tag = m[1];
                    if (tag.lastIndexOf("begin_", 0)) {
                        startLine = n;
                    }
                    else if (tag === "end_compilation") {
                        
                    }
                }
            }))
            .on("end", () => {
                cb(this.methods)
            });
    }
}