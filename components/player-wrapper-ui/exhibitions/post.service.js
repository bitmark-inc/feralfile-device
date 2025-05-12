const YOUTUBE_VIDEO_QUERY_PARAM_KEY = 'v';
const YOUTUBE_URL = 'https://www.youtube.com';
const YOUTUBE_THUMBNAIL_URL =
  'https://img.youtube.com/vi/{video-id}/{variant}.jpg';
const YOUTUBE_VIDEO_URL = 'https://www.youtube.com/embed/{video-id}';
const YoutubeThumbnailVariants = [
  'maxresdefault', // Higher quality - May or may not exist
  'mqdefault', // Lower quality - Guaranteed to exist
]

export const PostType = {
  CuratorNote:   "Curator's note",
  ArtistNote:    "Artist's note",
  CloseUp:       "close-up",
  Event:         "event",
  News:          "news",
  Schedule:      "schedule",
  WhitePaper:    "white-paper",
  J043Custom:    "jg043-custom",
  Foreword:      "foreword"
};

export function getFormattedPosts(exhibition) {
  try {
    let posts = exhibition.posts ?? [];
    const curatorNote = {
      id: 'curatorNote',
      type: PostType.CuratorNote,
      title: exhibition.noteTitle,
      content: exhibition.noteBrief,
    }

    posts = [curatorNote, ...posts];

    for (const post of posts) {
      formatPost(post);
    }
    return posts;
  } catch (error) {
    console.log(
      '[API] Failed to load post exhibition:',
      JSON.stringify(error)
    );
    return [];
  }
}

function formatPost(resource) {
  try {
    if (!resource.coverURI) {
      return;
    }

    const url = new URL(resource.coverURI);
    if (url.hostname === new URL(YOUTUBE_URL).hostname) {
      const videoId = url.searchParams.get(YOUTUBE_VIDEO_QUERY_PARAM_KEY);
      resource.mediaType = 'video';
      if (videoId) {
        resource.thumbUrls = [];
        for (const variant of YoutubeThumbnailVariants) {
          resource.thumbUrls.push(
            YOUTUBE_THUMBNAIL_URL.replaceAll(
              /{video-id}/g,
              videoId
            ).replaceAll(/{variant}/g, variant)
          );
        }

        resource.videoUrl = YOUTUBE_VIDEO_URL.replace('{video-id}', videoId);
      }
    } else {
      resource.thumbUrls = [resource.coverURI];
    }
  } catch (error) {
    console.log('[API] Failed to format post:', JSON.stringify(error));
    Sentry.captureException(error);
  }
}
