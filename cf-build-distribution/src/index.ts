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
      const key = url.pathname.replace('/pool/', '');
      const object = await env.BUCKET.get(key);
      
      if (!object) {
        return new Response('File not found', { status: 404 });
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
      const key = url.pathname.replace('/dists/', '');
      if (key.endsWith('/Release') || key.endsWith('/InRelease')) {
        // Serve the Release file
        const object = await env.BUCKET.get(key);
        if (!object) {
          return new Response(`${key} not found`, { status: 404 });
        }
        
        return new Response(object.body, {
          headers: {
            'Content-Type': 'text/plain',
            'Content-Length': object.size.toString(),
            'Cache-Control': 'max-age=3600, public',
          },
        });
      }

      if (key.endsWith('main/binary-arm64/Packages')) {
        const branch = key.replace('main/binary-arm64/Packages', '');
        // Serve the Packages file
        const object = await env.BUCKET.get(branch+'Packages');
        if (!object) {
          return new Response(`${branch+'Packages'} not found`, { status: 404 });
        }
    
        return new Response(object.body, {
          headers: {
            'Content-Type': 'text/plain',
            'Content-Length': object.size.toString(),
            'Cache-Control': 'max-age=3600, public',
          },
        });
      }
    
      if (key.endsWith('main/binary-arm64/Packages.gz')) {
        const branch = key.replace('main/binary-arm64/Packages.gz', '');
        // Serve the Packages file
        const object = await env.BUCKET.get(branch+'Packages.gz');
        if (!object) {
          return new Response(`${branch+'Packages.gz'} not found`, { status: 404 });
        }
    
        return new Response(object.body, {
          headers: {
            'Content-Type': 'application/gzip',
            'Content-Encoding': 'gzip',
            'Content-Length': object.size.toString(),
            'Cache-Control': 'max-age=3600, public',
          },
        });
      }
    
      return new Response('Path not found', { status: 404 });
    }

    // List files and generate HTML
    const files = await listFiles(env.BUCKET);
    const html = generateHtml(files);

    return new Response(html, {
      headers: { 'Content-Type': 'text/html' },
    });
  },
}; 