interface FileInfo {
  branch: string;
  version: string;
  debUrl: string;
  zipUrl: string;
}

interface VersionInfo {
  latest_version: string;
  image_url: string;
  app_url: string;
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
        } else {
          files.push({
            branch,
            version,
            debUrl: obj.key,
            zipUrl: '',
          });
        }
      }
    } else if (filename.includes('feralfile_device')) {
      const version = filename.match(/device_(.+?)\.zip/)?.[1];
      if (version) {
        const existing = files.find(f => f.branch === branch && f.version === version);
        if (existing) {
          existing.zipUrl = obj.key;
        } else {
          files.push({
            branch,
            version,
            debUrl: '',
            zipUrl: obj.key,
          });
        }
      }
    }
  }

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