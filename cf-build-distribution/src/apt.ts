import { Env } from './index';

interface PackageInfo {
  name: string;
  version: string;
  architecture: string;
  maintainer: string;
  depends: string;
  filename: string;
  size: number;
  md5sum: string | null;
  sha1: string | null;
  sha256: string | null;
  section: string;
  priority: string;
  description: string;
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

function bufferToHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

async function generatePackagesContent(branch: string, env: Env): Promise<string> {
  console.log(`Generating Packages content for branch: ${branch}`);
  
  const objects = await env.BUCKET.list({ prefix: branch, delimiter: '/' });
  const debFiles = objects.objects.filter(obj => obj.key.endsWith('.deb'));
  
  console.log(`Found ${debFiles.length} .deb files:`, debFiles.map(f => f.key));

  const packages: PackageInfo[] = [];
  
  for (const file of debFiles) {
    const object = await env.BUCKET.head(file.key);
    if (!object) {
      console.log(`Could not get object for key: ${file.key}`);
      continue;
    }

    const size = object.size;
    const versionMatch = file.key.match(/_([0-9]+\.[0-9]+\.[0-9]+)_/);
    const version = versionMatch ? versionMatch[1] : 'unknown';

    console.log(`Processing .deb file: ${file.key}, version: ${version}, size: ${size}`);

    packages.push({
      name: 'feralfile-launcher',
      version,
      architecture: 'arm64',
      maintainer: 'Bitmark Inc <support@feralfile.com>',
      depends: 'gldriver-test, chromium, rpi-chromium-mods, fonts-droid-fallback, fonts-liberation2, x11-xserver-utils, xdotool, xserver-xorg, xserver-xorg-video-fbdev, xinit, openbox, lightdm, bluez, zenity, jq, unattended-upgrades',
      filename: `pool/${file.key}`,
      size,
      md5sum: object.checksums?.md5 ? bufferToHex(object.checksums.md5) : null,
      sha1: object.checksums?.sha1 ? bufferToHex(object.checksums.sha1) : null,
      sha256: object.checksums?.sha256 ? bufferToHex(object.checksums.sha256) : null,
      section: 'base',
      priority: 'optional',
      description: 'Feral File Connection Assistant'
    });
  }

  const content = packages.map(pkg => `
Package: ${pkg.name}
Version: ${pkg.version}
Architecture: ${pkg.architecture}
Maintainer: ${pkg.maintainer}
Depends: ${pkg.depends}
Filename: ${pkg.filename}
Size: ${pkg.size}
${pkg.md5sum ? `MD5sum: ${pkg.md5sum}` : ''}
${pkg.sha1 ? `SHA1: ${pkg.sha1}` : ''}
${pkg.sha256 ? `SHA256: ${pkg.sha256}` : ''}
Section: ${pkg.section}
Priority: ${pkg.priority}
Description: ${pkg.description}
`).join('\n').trim();

  console.log(`Generated Packages content length: ${content.length}`);
  return content;
}

async function gzip(content: string): Promise<ArrayBuffer> {
  const stream = new Response(content).body;
  const cs = new CompressionStream('gzip');
  const compressedStream = stream?.pipeThrough(cs);
  const response = new Response(compressedStream);
  return await response.arrayBuffer();
}