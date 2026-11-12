//
//  YouTube.js
//  FineTune (BeardedSpice Strategy)
//

BSStrategy = {
  version: 5,
  displayName: "YouTube",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*youtube.com/*' && !%K LIKE[c] '*music.youtube.com*'",
    args: ["URL", "URL"]
  },
  isPlaying: function () {
    var v = document.querySelector('#movie_player video') || document.querySelector('video');
    return v ? (!v.paused && !v.ended) : false;
  },
  toggle: function () {
    var p = document.querySelector('#movie_player');
    if (p && typeof p.getPlayerState === 'function') {
      if (p.getPlayerState() === 1) { p.pauseVideo(); } else { p.playVideo(); }
      return;
    }
    var btn = document.querySelector('#movie_player .ytp-play-button, .ytp-play-button');
    if (btn) { btn.click(); return; }
    var v = document.querySelector('video');
    if (v) { if (v.paused) v.play(); else v.pause(); }
  },
  previous: function () {
    var p = document.querySelector('#movie_player');
    if (p && typeof p.previousVideo === 'function') { p.previousVideo(); return; }
    var btn = document.querySelector('.ytp-prev-button');
    if (btn && btn.style.display !== 'none') { btn.click(); return; }
    var v = document.querySelector('video');
    if (v) { v.currentTime = 0; }
  },
  next: function () {
    var p = document.querySelector('#movie_player');
    if (p && typeof p.nextVideo === 'function') { p.nextVideo(); return; }
    var btn = document.querySelector('.ytp-next-button');
    if (btn) { btn.click(); }
  },
  pause: function () {
    var p = document.querySelector('#movie_player');
    if (p && typeof p.pauseVideo === 'function') { p.pauseVideo(); return; }
    var v = document.querySelector('video');
    if (v && !v.paused) { v.pause(); }
  },
  favorite: function () {
    var btn = document.querySelector('like-button-view-model button, #segmented-like-button button, ytd-toggle-button-renderer button');
    if (btn) { btn.click(); }
  },
  trackInfo: function () {
    var meta = (navigator.mediaSession && navigator.mediaSession.metadata) ? navigator.mediaSession.metadata : null;
    var titleEl = document.querySelector('h1.ytd-watch-metadata yt-formatted-string, #title h1');
    var authorEl = document.querySelector('#upload-info #channel-name a, ytd-channel-name a');
    var track = (meta && meta.title) ? meta.title : (titleEl ? titleEl.textContent.trim() : document.title.replace(/ - YouTube$/, ''));
    var artist = (meta && meta.artist) ? meta.artist : (authorEl ? authorEl.textContent.trim() : 'YouTube');
    var img = (meta && meta.artwork && meta.artwork.length) ? meta.artwork[meta.artwork.length - 1].src : '';
    var likeBtn = document.querySelector('like-button-view-model button, #segmented-like-button button');
    var fav = likeBtn ? (likeBtn.getAttribute('aria-pressed') === 'true') : false;
    return {
      'image': img,
      'track': track,
      'artist': artist,
      'favorited': fav
    };
  }
}
