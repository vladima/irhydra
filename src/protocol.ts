export namespace LoadHydrogenLog {
    export const RequestChannel = "request:load-hydrogen-log";
    export interface Request {
        path: string;
    }

    export const ResponseChannel = "response:load-hydrogen-log"
    export interface Response {
        methods: Method[];
    }

    export interface MethodName {
        full: string;
        source: string;
        short: string;
    }

    export interface Method {
        name: MethodName;
        optId: string;
        phases: Phase[];
    }
    
    export interface Phase {
        name: string;
        startLine: number;
        endLine: number;
    }
}

