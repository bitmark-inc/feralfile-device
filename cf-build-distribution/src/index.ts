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

    if (url.pathname.startsWith('/pool/')) {
      const key = url.pathname.substring(1);
      const object = await env.BUCKET.get(key);
      
      if (!object) {
        console.error(`File not found for key: ${key}`);
        return new Response(`File not found: ${url.pathname}`, { status: 404 });
      }

      return new Response(object.body, {
        headers: {
          'Content-Type': 'application/x-debian-package',
          'Content-Length': object.size.toString(),
          'Cache-Control': 'max-age=3600, public',
        },
      });
    }

    // Handle release notes
    if (url.pathname.startsWith('/api/release-notes/')) {
      const fullPath = decodeURIComponent(url.pathname.replace('/api/release-notes/', ''));
      const match = fullPath.match(/(.+)\/(.+)$/);  // Split at the last slash
      if (!match) {
        return new Response('Invalid release notes path', { status: 400 });
      }
      
      const [_, branch, version] = match;
      const key = `${branch}/release_notes_${version}.md`;
      
      console.log('Looking for release notes at:', key); // For debugging
      
      const object = await env.BUCKET.get(key);
      
      if (!object) {
        return new Response('Release notes not found', { status: 404 });
      }

      return new Response(await object.text(), {
        headers: { 'Content-Type': 'text/markdown' }
      });
    }

    // Handle apt request
    if (url.pathname.startsWith('/dists/')) {
      const pathParts = url.pathname.substring('/dists/'.length).split('/');
      
      if (pathParts.length < 4) {
        return new Response('Invalid APT repository path structure', { status: 400 });
      }

      const branch = pathParts[0];
      const component = pathParts[1];
      const archComponent = pathParts[2];
      const filename = pathParts[pathParts.length - 1];

      if (filename === 'Release' || filename === 'InRelease') {
        const key = `${branch}/${filename}`;
        const object = await env.BUCKET.get(key);
        if (!object) {
          return new Response(`${key} not found`, { status: 404 });
        }
        
        return new Response(object.body, {
          headers: {
            'Content-Type': 'text/plain',
            'Content-Length': object.size.toString(),
            'Cache-Control': 'public, max-age=3600, must-revalidate',
          },
        });
      }

      const archMatch = archComponent.match(/^binary-(amd64|arm64)$/);
      if (!archMatch || (filename !== 'Packages' && filename !== 'Packages.gz')) {
        console.error(`Invalid APT path or filename: ${url.pathname}`);
        return new Response('Invalid APT repository path or file requested', { status: 400 });
      }
      
      const arch = archMatch[1];

      const r2Filename = filename === 'Packages' ? `Packages-${arch}` : `Packages.gz-${arch}`;
      const key = `${branch}/${r2Filename}`;

      console.log(`Attempting to fetch APT file from R2 key: ${key}`);

      const object = await env.BUCKET.get(key);
      if (!object) {
        console.error(`APT file not found in R2 at key: ${key}`);
        return new Response(`APT file ${key} not found`, { status: 404 });
      }

      let contentType = 'text/plain';
      let contentEncoding: string | null = null;
      if (filename === 'Packages.gz') {
        contentType = 'application/gzip';
        contentEncoding = 'gzip';
      }

      const headers: HeadersInit = {
        'Content-Type': contentType,
        'Content-Length': object.size.toString(),
        'Cache-Control': 'public, max-age=3600',
      };
      if (contentEncoding) {
        headers['Content-Encoding'] = contentEncoding;
      }

      return new Response(object.body, { headers });
    }

    // List files and generate HTML
    const files = await listFiles(env.BUCKET);
    const html = generateHtml(files);

    return new Response(html, {
      headers: { 'Content-Type': 'text/html' },
    });
  },
}; 