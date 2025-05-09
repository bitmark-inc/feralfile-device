import { exhibitionDetail } from '../data.js';

const ExhibitionType = { group: 'group', solo: 'solo' };

const screenRatio = window.innerWidth / 1920;
const FERAL_FILE_ASSET_URL = 'https://cdn.feralfileassets.com/';

(function renderExhibitionCard() {
  const root = document.getElementById('exhCard');
  // set base font-size
  root.style.fontSize = `${22 * screenRatio}px`;

  // LEFT SECTION
  const left = document.createElement('div');
  left.className = 'left-section';
  left.style.padding = `${60 * screenRatio}px`;

  const info = document.createElement('div');
  info.className = 'info';
  info.style.rowGap = `${40 * screenRatio}px`;

  // Title
  const title = document.createElement('p');
  title.className = 'title';
  title.style.fontSize = `${48 * screenRatio}px`;
  title.textContent = exhibitionDetail.title;
  info.appendChild(title);

  // Curator (if present)
  if (exhibitionDetail.curatorAlumni) {
    const cWrap = document.createElement('div');

    const cLabel = document.createElement('p');
    cLabel.className = 'sub-title';
    cLabel.style.fontSize = `${18 * screenRatio}px`;
    cLabel.textContent = 'Curator';
    cWrap.appendChild(cLabel);

    const cName = document.createElement('p');
    cName.textContent = exhibitionDetail.curatorAlumni.alias;
    cWrap.appendChild(cName);

    info.appendChild(cWrap);
  }

  // Exhibition type + artists
  const tWrap = document.createElement('div');

  if (exhibitionDetail.type === ExhibitionType.group) {
    const tLabel = document.createElement('p');
    tLabel.className = 'sub-title';
    tLabel.style.fontSize = `${18 * screenRatio}px`;
    tLabel.textContent = 'Group Exhibition';
    tWrap.appendChild(tLabel);
  }
  if (exhibitionDetail.type === ExhibitionType.solo) {
    const tLabel = document.createElement('p');
    tLabel.className = 'sub-title';
    tLabel.style.fontSize = `${18 * screenRatio}px`;
    tLabel.textContent = 'Solo Exhibition';
    tWrap.appendChild(tLabel);
  }

  if (exhibitionDetail.artistsAlumni?.length) {
    const artists = document.createElement('p');
    artists.textContent = exhibitionDetail.artistsAlumni
      .map(a => a.alias)
      .join(', ');
    tWrap.appendChild(artists);
  }

  info.appendChild(tWrap);
  left.appendChild(info);
  root.appendChild(left);

  // RIGHT SECTION
  const right = document.createElement('div');
  right.className = 'right-section';

  const imgContainer = document.createElement('div');
  imgContainer.style.width = '100%';
  imgContainer.style.height = '100%';

  const img = document.createElement('img');
  img.src = FERAL_FILE_ASSET_URL + exhibitionDetail.coverURI;
  img.alt = exhibitionDetail.title;

  imgContainer.appendChild(img);
  right.appendChild(imgContainer);
  root.appendChild(right);
})();