import { exhibitionDetail } from '../data.js';
import { PostType, getFormattedPosts } from '../post.service.js';

const screenRatio = window.innerWidth / window.innerHeight;
const youtubeFailedThumbnailHeight = 90;

function formatDateTime(iso){
  const d = new Date(iso);
  const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  
  const dayName   = weekdays[d.getUTCDay()];
  const monthName = months[d.getUTCMonth()];
  const dayNum    = d.getUTCDate();
  const year      = d.getUTCFullYear();
  const hours     = String(d.getUTCHours()).padStart(2, "0");
  const minutes   = String(d.getUTCMinutes()).padStart(2, "0");

  return {
    date:  `${dayName}, ${monthName} ${dayNum}, ${year}`, 
    time:  `${hours}:${minutes}`
  };
}

function buildSlides() {
  const wrapper = document.getElementById('carousel-wrapper');
  const posts = getFormattedPosts(exhibitionDetail);

  posts.forEach(item => {
    if (item.dateTime && !item.date) {
      const ft = formatDateTime(item.dateTime);
      item.date = ft.date; item.time = ft.time;
    }

    const slide = document.createElement('div');
    slide.className = 'swiper-slide';

    const card = document.createElement('div');
    card.className = 'card';
    card.style.padding = `${(window.innerWidth > window.innerHeight ? 40 : 20) * screenRatio}px`;

    renderPostsCard(item, card);

    slide.append(card);
    wrapper.append(slide);
  });
}

function renderPostsCard(item, cardElement) {
  // helper to create a <p> with class, text, and inline font-size/margin
  function makeP(className, text, fontSize, marginTop) {
    const p = document.createElement('p');
    p.className = className;
    if (fontSize)  p.style.fontSize = `${fontSize * screenRatio}px`;
    if (marginTop) p.style.marginTop = `${marginTop * screenRatio}px`;
    p.textContent = text;
    return p;
  }

  // (1) ArtistNote or CuratorNote
  if (item.type === PostType.ArtistNote || item.type === PostType.CuratorNote) {
    cardElement.appendChild(makeP('type', item.type, 22));
    cardElement.appendChild(makeP('postTitle', item.title, 32, 45));
    const content = document.createElement('p');
    content.className = 'content';
    content.style.fontSize = `${32 * screenRatio}px`;
    content.style.marginTop = `${45 * screenRatio}px`;
    content.innerHTML = item.content || '';
    cardElement.appendChild(content);
  }

  // (2) J043Custom or Foreword
  else if (item.type === PostType.J043Custom || item.type === PostType.Foreword) {
    cardElement.appendChild(makeP('type', item.title, 32));
    const content = document.createElement('p');
    content.className = 'content';
    content.style.fontSize = `${32 * screenRatio}px`;
    content.style.marginTop = `${45 * screenRatio}px`;
    content.innerHTML = item.content || '';
    cardElement.appendChild(content);
  }

  // (3) CloseUp
  else if (item.type === PostType.CloseUp) {
    cardElement.appendChild(makeP('type', 'Close up', 22));
    if (item.thumbUrls && item.thumbUrls.length) {
      const thumbDiv = document.createElement('div');
      thumbDiv.className = `thumbnail ${window.viewMode == 'landscape' ? 'landscapeThumbnail' : 'portraitThumbnail'}`;
      thumbDiv.style.marginTop = `${45 * screenRatio}px`;
      item.thumbUrls.forEach(url => {
        const img = document.createElement('img');
        img.src = url;
        img.alt = 'thumbnail';
        thumbDiv.appendChild(img);
      });
      cardElement.appendChild(thumbDiv);
    }
    cardElement.appendChild(makeP('postTitle', item.title, 32, 45));
    if (item.author) {
      cardElement.appendChild(makeP('subContent', `by ${item.author}`, 26, 45));
    }
  }

  // (4) Event, News, Schedule, WhitePaper
  else if ([PostType.Event,PostType.News,PostType.Schedule,PostType.WhitePaper].includes(item.type)) {
    // type label
    const label = item.type === PostType.WhitePaper ? 'White paper' : item.type;
    const pType = makeP('type capitalizedFirstChar', label, 22);
    cardElement.appendChild(pType);
    // thumbnail if any
    if (item.thumbUrls && item.thumbUrls.length) {
      const thumbDiv = document.createElement('div');
      thumbDiv.className = 'thumbnail';
      thumbDiv.style.marginTop = `${45 * screenRatio}px`;
      const img = document.createElement('img');
      img.src = item.thumbUrls[0]; // the default thumbnail index is 0
      img.alt = 'thumbnail';
      img.addEventListener('load', () => onPostThumbnailLoad(item.thumbUrls, 0, img));

      thumbDiv.appendChild(img);
      cardElement.appendChild(thumbDiv);
    }
    // title
    cardElement.appendChild(makeP('postTitle', item.title, 32, 45));
    // date/time block
    if (item.date && item.time) {
      const dt = document.createElement('div');
      dt.className = 'content';
      dt.style.fontSize = `${32 * screenRatio}px`;
      dt.style.marginTop = `${45 * screenRatio}px`;
      dt.innerHTML = `<p>Date: ${item.date}</p><p>Time: ${item.time}</p>`;
      cardElement.appendChild(dt);
    }
    // author
    if (item.author) {
      cardElement.appendChild(makeP('subContent', `by ${item.author}`, 26, 45));
    }
  }

  return cardElement;
}

function onPostThumbnailLoad(urls, currentIndex, imgElement) {
  if (imgElement.naturalHeight <= youtubeFailedThumbnailHeight) {
    if (currentIndex < urls.length - 1) {
      const nextIndex = currentIndex + 1;
      imgElement.src = urls[nextIndex];
    } else {
      imgElement.src = undefined; // No valid image found
    }
  }
}

function initCarousel() {
  buildSlides();

  const gap = Math.round(window.innerWidth * 0.08);

  new Swiper('.swiper-container', {
    effect: 'coverflow',
    coverflowEffect: {
      rotate:0,
      stretch:0,
      depth:250,
      modifier:1,
      slideShadows:false,
      scale:0.7
    },
    slidesPerView: 'auto',
    centeredSlides: true,
    spaceBetween: gap,
    loop: false
  });
}

window.addEventListener('load', initCarousel);
window.addEventListener('resize', ()=> location.reload());
