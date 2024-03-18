import * as http from 'http';

type HandlerFunction = () => string;

class FnServer {
  private static instance: FnServer;
  private functions: { [key: string]: HandlerFunction } = {};
  private serverStarted: boolean = false;

  private constructor() {}

  public static getInstance(): FnServer {
    if (!FnServer.instance) {
      FnServer.instance = new FnServer();
    }
    return FnServer.instance;
  }

  public handle(name: string, fn: HandlerFunction): void {
    const slug: string = name.replace(/\s+/g, '-').toLowerCase();
    this.functions[`/${slug}`] = fn;

    // Automatically start the server when the first function is registered
    if (!this.serverStarted) {
      this.start();
    }
  }

  private start(port: number = 3000): void {
    if (this.serverStarted) return; // Prevent starting the server more than once

    const server = http.createServer((req, res) => {
      const fn = this.functions[req.url || ''];
      if (fn && req.method === 'GET') {
        let response: string;
        try {
          response = fn();
          res.statusCode = 200;
        } catch (error) {
          console.error(`Error executing function for ${req.url}:`, error);
          res.statusCode = 500;
          response = 'Internal Server Error';
        }
        res.end(response);
      } else {
        res.statusCode = 404;
        res.end('Not Found');
      }
    });

    server.listen(port, '0.0.0.0', () => {
      console.log(`FnServer running at http://0.0.0.0:${port}/`);
      this.serverStarted = true;
    });
  }
}

export default FnServer.getInstance();
