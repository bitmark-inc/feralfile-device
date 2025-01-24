import { FileInfo } from './r2';

export function generateHtml(files: FileInfo[]): string {
  const lastUpdated = new Date().toLocaleString();
  
  // Group files by branch
  const groupedFiles = files.reduce((acc, file) => {
    if (!acc[file.branch]) {
      acc[file.branch] = [];
    }
    acc[file.branch].push(file);
    // Sort versions within each branch by lastUpdated (newest first)
    acc[file.branch].sort((a, b) => (b.lastUpdated || 0) - (a.lastUpdated || 0));
    return acc;
  }, {} as Record<string, FileInfo[]>);

  return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Feral File Device Distribution</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        .version-history {
            background: #f8f9fa;
            border-top: 1px solid #dee2e6;
        }
        .version-history td {
            padding-left: 2rem;
        }
        .expand-btn {
            cursor: pointer;
            user-select: none;
        }
        .expand-btn:hover {
            color: #0d6efd;
        }
    </style>
</head>
<body class="bg-light">
    <div class="container py-5">
        <div class="row mb-4">
            <div class="col">
                <h1 class="display-4">Feral File Device Distribution</h1>
                <p class="text-muted">Last Updated: ${lastUpdated}</p>
            </div>
        </div>

        <div class="row">
            <div class="col">
                <div class="card shadow-sm">
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-hover">
                                <thead>
                                    <tr>
                                        <th style="width: 1%"></th>
                                        <th>Branch</th>
                                        <th>Version</th>
                                        <th>Last Updated</th>
                                        <th>Image</th>
                                        <th>App Package</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${Object.entries(groupedFiles).map(([branch, branchFiles]) => `
                                    <tr>
                                        <td class="expand-btn" data-branch="${branch}" onclick="toggleVersions('${branch}')">
                                            ${branchFiles.length > 1 ? '▶' : ''}
                                        </td>
                                        <td>
                                            ${branch}
                                            ${branch.startsWith('releases/') 
                                              ? '<span class="ms-2 badge bg-success">release</span>'
                                              : branch === 'main'
                                                ? '<span class="ms-2 badge bg-primary">stable</span>'
                                                : '<span class="ms-2 badge bg-warning text-dark">development</span>'
                                            }
                                        </td>
                                        <td>${branchFiles[0].version}</td>
                                        <td>${new Date(branchFiles[0].lastUpdated || Date.now()).toLocaleString()}</td>
                                        <td>
                                            ${branchFiles[0].zipUrl ? `
                                            <a href="/download/${branchFiles[0].zipUrl}" class="btn btn-sm btn-outline-primary">
                                                Download Image
                                                ${branchFiles[0].zipSize ? `<span class="ms-2 badge bg-secondary">${branchFiles[0].zipSize}</span>` : ''}
                                            </a>` : '-'}
                                        </td>
                                        <td>
                                            ${branchFiles[0].debUrl ? `
                                            <a href="/download/${branchFiles[0].debUrl}" class="btn btn-sm btn-outline-secondary">
                                                Download .deb
                                                ${branchFiles[0].debSize ? `<span class="ms-2 badge bg-secondary">${branchFiles[0].debSize}</span>` : ''}
                                            </a>` : '-'}
                                        </td>
                                    </tr>
                                    ${branchFiles.slice(1).map(file => `
                                    <tr class="version-history d-none" data-branch="${branch}">
                                        <td></td>
                                        <td colspan="2">${file.version}</td>
                                        <td>${new Date(file.lastUpdated || Date.now()).toLocaleString()}</td>
                                        <td>
                                            ${file.zipUrl ? `
                                            <a href="/download/${file.zipUrl}" class="btn btn-sm btn-outline-primary">
                                                Download Image
                                                ${file.zipSize ? `<span class="ms-2 badge bg-secondary">${file.zipSize}</span>` : ''}
                                            </a>` : '-'}
                                        </td>
                                        <td>
                                            ${file.debUrl ? `
                                            <a href="/download/${file.debUrl}" class="btn btn-sm btn-outline-secondary">
                                                Download .deb
                                                ${file.debSize ? `<span class="ms-2 badge bg-secondary">${file.debSize}</span>` : ''}
                                            </a>` : '-'}
                                        </td>
                                    </tr>
                                    `).join('')}
                                    `).join('')}
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    <script>
    function toggleVersions(branch) {
        const btn = document.querySelector(\`.expand-btn[data-branch="\${branch}"]\`);
        const rows = document.querySelectorAll(\`.version-history[data-branch="\${branch}"]\`);
        const isExpanded = rows[0]?.classList.contains('d-none') === false;
        
        rows.forEach(row => row.classList.toggle('d-none'));
        btn.textContent = isExpanded ? '▶' : '▼';
    }
    </script>
</body>
</html>
`;
} 