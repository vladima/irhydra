import { LoadHydrogenLog } from "./protocol";
import * as fs from "fs";
import * as es from "event-stream";

const enum Missing { Value = -1 }

export default class HydrogenLog {
    private lines: string[];
    private methods: LoadHydrogenLog.Method[];

    // preparses file using logic from irhydra/irhydra/lib/src/modes/v8/name_parser.dart
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
        const methodRe = /\s+method "([^"]*)"/;
        const optIdRe = /:(\d+)$/;

        let startLine = Missing.Value;

        let method: LoadHydrogenLog.Method;

        fs.createReadStream(path)
            .pipe(es.split(/\n/))
            .pipe(es.mapSync((line) => {
                const n = this.lines.length;
                this.lines.push(line);

                const m = tagRe.exec(line);
                if (!m) {
                    return;
                }
                const tag = m[0];
                if (tag.lastIndexOf("begin_", 0) !== -1) {
                    startLine = n;
                }
                else if (tag === "end_compilation") {
                    const s = startLine + 1; // line after the start tag
                    const e = n - 1; // line before the end tag
                    const name = nameRe.exec(this.lines[s])[1];
                    const optIdMatch = methodRe.exec(this.lines[s + 1]);
                    let optId: string;
                    if (optIdMatch) {
                        optId = optIdRe.exec(optIdMatch[1])[1];
                    }
                    method = {
                        name: this.parseName(name),
                        optId,
                        phases: []
                    }
                    this.methods.push(method);
                }
                else if (tag === "end_cfg") {
                    const name = nameRe.exec(this.lines[startLine + 1])[1];
                    method.phases.push({ name, startLine, endLine: n })
                }
            }))
            .on("end", () => {
                cb(this.methods)
            });
    }
    
    public getPhaseBodyText(startLine: number, endLine: number): string {
        let text = "";
        for (let i = startLine; i < endLine; ++i) {
            if (i != startLine) {
                text += "\n";
            }
            text += this.lines[i];
        }
        return text;
    }

    // parsed method name using logic from irhydra/irhydra/lib/src/modes/v8/name_parser.dart
    public parseName(text: string): LoadHydrogenLog.MethodName {
        const index = text.indexOf("$");
        if (index === -1) {
            return { full: text, source: undefined, short: text };
        }
        if (text.length > 1 &&
            text.charAt(0) === "$" &&
            text.charAt(text.length - 1) === "$") {
            text = text.substring(1, text.length - 1);
        }
        const lastIndex = text.lastIndexOf("$");
        if (lastIndex === 0 || lastIndex === text.length - 1) {
            return { full: text, source: undefined, short: text };
        }
        const source = text.substring(0, lastIndex - ((text.charAt(lastIndex - 1) === "$") ? 1 : 0));
        const short = text.substring(lastIndex + 1);
        return { full: text, source, short };
    }
}