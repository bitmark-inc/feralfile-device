import { FileInfo } from './r2';

export function generateHtml(files: FileInfo[]): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Feral File Device Distribution</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      max-width: 1200px;
      margin: 0 auto;
      padding: 20px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 20px;
    }
    th, td {
      padding: 12px;
      text-align: left;
      border-bottom: 1px solid #ddd;
    }
    th {
      background-color: #f5f5f5;
    }
    a {
      color: #0066cc;
      text-decoration: none;
      margin-right: 15px;
    }
    a:hover {
      text-decoration: underline;
    }
    .version-cell {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }

    /* Modal styles */
    .modal {
      display: none;
      position: fixed;
      z-index: 1;
      left: 0;
      top: 0;
      width: 100%;
      height: 100%;
      overflow: auto;
      background-color: rgba(0,0,0,0.4);
    }

    .modal-content {
      background-color: #fefefe;
      margin: 15% auto;
      padding: 20px;
      border: 1px solid #888;
      width: 90%;
      max-width: 700px;
      border-radius: 8px;
      position: relative;
    }

    .close {
      position: absolute;
      right: 20px;
      top: 10px;
      color: #aaa;
      font-size: 28px;
      font-weight: bold;
      cursor: pointer;
    }

    .close:hover {
      color: black;
    }

    .guide-step {
      margin: 20px 0;
      padding: 15px;
      background: #f8f9fa;
      border-radius: 5px;
    }

    .guide-step img {
      max-width: 100%;
      height: auto;
      margin: 10px 0;
    }

    @media (max-width: 768px) {
      body {
        padding: 10px;
      }
      th, td {
        padding: 8px;
      }
      .modal-content {
        margin: 10% auto;
        width: 95%;
      }
    }
  </style>
</head>
<body>
  <h1>Feral File Distribution</h1>
  <table>
    <thead>
      <tr>
        <th>Branch</th>
        <th>Version</th>
        <th>Downloads</th>
      </tr>
    </thead>
    <tbody>
      ${files.map(file => `
        <tr>
          <td>${file.branch}</td>
          <td>${file.version}</td>
          <td>
            <div class="version-cell">
              ${file.debUrl ? `<a href="/download/${file.debUrl}">Download Feral File launcher app (Expert only)</a>` : ''}
              ${file.zipUrl ? `<a href="/download/${file.zipUrl}">Download Raspberry Pi Image</a> <a href="#" onclick="showGuide(event)">How to flash</a>` : ''}
            </div>
          </td>
        </tr>
      `).join('')}
    </tbody>
  </table>

  <!-- Flash Guide Modal -->
  <div id="flashGuide" class="modal">
    <div class="modal-content">
      <span class="close" onclick="closeGuide()">&times;</span>
      <h2>How to Flash the Image Using balenaEtcher</h2>
      
      <div class="guide-step">
        <h3>Step 1: Download and Install balenaEtcher</h3>
        <p>First, download and install balenaEtcher from <a href="https://www.balena.io/etcher" target="_blank">https://www.balena.io/etcher</a></p>
      </div>

      <div class="guide-step">
        <h3>Step 2: Prepare Your SD Card</h3>
        <p>Insert your SD card into your computer using a card reader. Note: All data on the SD card will be erased during flashing.</p>
      </div>

      <div class="guide-step">
        <h3>Step 3: Flash the Image</h3>
        <ol>
          <li>Open balenaEtcher</li>
          <li>Click "Flash from file" and select the downloaded image file</li>
          <li>Click "Select target" and choose your SD card</li>
          <li>Click "Flash!" to begin the process</li>
          <li>Wait for the flashing and verification process to complete</li>
        </ol>
      </div>

      <div class="guide-step">
        <h3>Step 4: Insert SD Card and Boot</h3>
        <p>Once flashing is complete:</p>
        <ol>
          <li>Remove the SD card from your computer</li>
          <li>Insert it into your Raspberry Pi</li>
          <li>Connect power to boot up your device</li>
        </ol>
      </div>
    </div>
  </div>

  <script>
    function showGuide(event) {
      event.preventDefault();
      document.getElementById('flashGuide').style.display = 'block';
    }

    function closeGuide() {
      document.getElementById('flashGuide').style.display = 'none';
    }

    // Close modal when clicking outside of it
    window.onclick = function(event) {
      const modal = document.getElementById('flashGuide');
      if (event.target == modal) {
        modal.style.display = 'none';
      }
    }
  </script>
</body>
</html>
`;
} 