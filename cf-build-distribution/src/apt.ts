import { Env } from './index';

interface PackageInfo {
  name: string;
  version: string;
  architecture: string;
  maintainer: string;
  description: string;
  size: number;
  sha256: string;
  filename: string;
}

// Add GPG signing functions
async function signInRelease(content: string, env: Env): Promise<string> {
  return `-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

${content}
-----BEGIN PGP SIGNATURE-----

${env.APT_GPG_PUBLIC_KEY}
-----END PGP SIGNATURE-----`;
}

function formatDate(): string {
  return new Date().toUTCString();
}

async function generateReleaseFile(branch: string, packagesContent: string, packagesGzContent: ArrayBuffer): Promise<string> {
  const packagesHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(packagesContent));
  const packagesGzHash = await crypto.subtle.digest('SHA-256', new Uint8Array(packagesGzContent));

  const toHex = (buffer: ArrayBuffer) => 
    Array.from(new Uint8Array(buffer))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

  return `Origin: feralfile-launcher
Label: Feral File Repository
Suite: stable
Codename: ${branch}
Architectures: arm64
Components: main
Description: Feral File Connection Assistant
Date: ${formatDate()}
SHA256:
 ${toHex(packagesHash)} ${packagesContent.length} main/binary-arm64/Packages
 ${toHex(packagesGzHash)} ${packagesGzContent.byteLength} main/binary-arm64/Packages.gz`;
}

export async function handleAptRequest(url: URL, env: Env): Promise<Response> {
  const key = url.pathname.replace('/dists/', '');

  if (key.endsWith('/Release') || key.endsWith('/InRelease')) {
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
    const content = await generatePackagesContent(branch, env);
    
    return new Response(content, {
      headers: {
        'Content-Type': 'text/plain',
        'Cache-Control': 'max-age=3600, public',
      },
    });
  }

  if (key.endsWith('main/binary-arm64/Packages.gz')) {
    const branch = key.replace('main/binary-arm64/Packages.gz', '');
    const content = await generatePackagesContent(branch, env);
    const gzipped = await gzip(content);

    return new Response(gzipped, {
      headers: {
        'Content-Type': 'application/gzip',
        'Cache-Control': 'max-age=3600, public',
      },
    });
  }

  return new Response('Path not found', { status: 404 });
}

async function generatePackagesContent(branch: string, env: Env): Promise<string> {
  const objects = await env.BUCKET.list({ prefix: `${branch}/`, delimiter: '/' });
  const debFiles = objects.objects.filter(obj => obj.key.endsWith('.deb'));

  const packages: PackageInfo[] = [];
  
  for (const file of debFiles) {
    const object = await env.BUCKET.get(file.key);
    if (!object) continue;

    const size = object.size;
    const sha256 = object.httpMetadata?.etag?.replace(/"/g, '') || '';
    const versionMatch = file.key.match(/_([0-9]+\.[0-9]+\.[0-9]+)_/);
    const version = versionMatch ? versionMatch[1] : 'unknown';

    packages.push({
      name: 'feralfile-launcher',
      version,
      architecture: 'arm64',
      maintainer: 'Bitmark Inc <support@feralfile.com>',
      description: 'Feral File Connection Assistant',
      size,
      sha256,
      filename: file.key
    });
  }

  return packages.map(pkg => `
Package: ${pkg.name}
Version: ${pkg.version}
Architecture: ${pkg.architecture}
Maintainer: ${pkg.maintainer}
Description: ${pkg.description}
Size: ${pkg.size}
SHA256: ${pkg.sha256}
Filename: pool/${pkg.filename}
`).join('\n').trim();
}

async function gzip(content: string): Promise<ArrayBuffer> {
  const stream = new Response(content).body;
  const cs = new CompressionStream('gzip');
  const compressedStream = stream?.pipeThrough(cs);
  const response = new Response(compressedStream);
  return await response.arrayBuffer();
}