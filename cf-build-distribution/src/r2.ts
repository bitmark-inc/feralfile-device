interface FileInfo {
  branch: string;
  version: string;
  debUrl: string;
  zipUrl: string;
  debSize?: string;
  zipSize?: string;
}

interface VersionInfo {
  latest_version: string;
  image_url: string;
  app_url: string;
}

function formatFileSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unitIndex = 0;
  
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  
  return `${size.toFixed(1)} ${units[unitIndex]}`;
}

export async function listFiles(bucket: R2Bucket): Promise<FileInfo[]> {
  const objects = await bucket.list();
  const files: FileInfo[] = [];
  
  for (const obj of objects.objects) {
    const [branch, filename] = obj.key.split('/');
    if (!filename) continue;

    if (filename.includes('feralfile_device_launcher')) {
      const version = filename.match(/launcher_(.+?)\.deb/)?.[1];
      if (version) {
        const existing = files.find(f => f.branch === branch && f.version === version);
        if (existing) {
          existing.debUrl = obj.key;
          existing.debSize = formatFileSize(obj.size);
        } else {
          files.push({
            branch,
            version,
            debUrl: obj.key,
            debSize: formatFileSize(obj.size),
            zipUrl: '',
            zipSize: undefined
          });
        }
      }
    } else if (filename.includes('feralfile_device')) {
      const version = filename.match(/device_(.+?)\.zip/)?.[1];
      if (version) {
        const existing = files.find(f => f.branch === branch && f.version === version);
        if (existing) {
          existing.zipUrl = obj.key;
          existing.zipSize = formatFileSize(obj.size);
        } else {
          files.push({
            branch,
            version,
            debUrl: '',
            debSize: undefined,
            zipUrl: obj.key,
            zipSize: formatFileSize(obj.size)
          });
        }
      }
    }
  }

  // Sort files by branch (main first) and then by version
  files.sort((a, b) => {
    // If one is main branch, it should come first
    if (a.branch === 'main') return -1;
    if (b.branch === 'main') return 1;
    
    // Otherwise sort branches alphabetically
    const branchCompare = a.branch.localeCompare(b.branch);
    if (branchCompare !== 0) return branchCompare;
    
    // If branches are equal, sort by version (assuming semantic versioning)
    const versionA = a.version.split('.').map(Number);
    const versionB = b.version.split('.').map(Number);
    
    for (let i = 0; i < 3; i++) {
      if (versionA[i] !== versionB[i]) {
        return versionB[i] - versionA[i]; // Descending order for versions
      }
    }
    return 0;
  });

  return files;
}

export async function getLatestVersion(bucket: R2Bucket, branch: string): Promise<VersionInfo | null> {
  const files = await listFiles(bucket);
  
  // Filter files by branch and find the latest version
  const branchFiles = files.filter(f => f.branch === branch);
  if (branchFiles.length === 0) return null;

  // Sort by version (assuming semantic versioning)
  branchFiles.sort((a, b) => {
    const versionA = a.version.split('.').map(Number);
    const versionB = b.version.split('.').map(Number);
    
    for (let i = 0; i < 3; i++) {
      if (versionA[i] !== versionB[i]) {
        return versionB[i] - versionA[i];
      }
    }
    return 0;
  });

  const latest = branchFiles[0];
  return {
    latest_version: latest.version,
    image_url: latest.zipUrl ? `/download/${latest.zipUrl}` : '',
    app_url: latest.debUrl ? `/download/${latest.debUrl}` : ''
  };
} 