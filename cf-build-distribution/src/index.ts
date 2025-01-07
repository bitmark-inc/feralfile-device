import { handleAuth } from './auth';
import { listFiles, getLatestVersion } from './r2';
import { generateHtml } from './html';

export interface Env {
  BUCKET: R2Bucket;
  AUTH_USERNAME: string;
  AUTH_PASSWORD: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // Handle authentication
    const authResponse = await handleAuth(request, env);
    if (authResponse) return authResponse;

    const url = new URL(request.url);
    
    // Handle API request
    if (url.pathname.startsWith('/api/latest/')) {
      const branch = url.pathname.replace('/api/latest/', '');
      const versionInfo = await getLatestVersion(env.BUCKET, branch);
      
      if (!versionInfo) {
        return new Response(JSON.stringify({ error: 'Branch not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      return new Response(JSON.stringify(versionInfo), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Handle file downloads
    if (url.pathname.startsWith('/download/')) {
      const key = url.pathname.replace('/download/', '');
      const object = await env.BUCKET.get(key);
      
      if (!object) {
        return new Response('File not found', { status: 404 });
      }

      return new Response(object.body, {
        headers: {
          'Content-Type': object.httpMetadata?.contentType || 'application/octet-stream',
          'Content-Disposition': `attachment; filename="${key.split('/').pop()}"`,
        },
      });
    }

    // List files and generate HTML
    const files = await listFiles(env.BUCKET);
    const html = generateHtml(files);

    return new Response(html, {
      headers: { 'Content-Type': 'text/html' },
    });
  },
}; 