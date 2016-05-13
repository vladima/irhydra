export namespace LoadHydrogenLog {
    export const RequestChannel= "request:load-hydrogen-log";
    export interface Request {
        path: string;
    }
    
    export const ResponseChannel = "response:load-hydrogen-log"
    export interface Response {
        methods: Method[];    
    }

    export interface Method {
        
    }
}

