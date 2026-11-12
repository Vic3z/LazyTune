//
//  YouTubeMusic.js
//  FineTune (BeardedSpice Strategy)
//

BSStrategy = {
  version: 2,
  displayName: "YouTube Music",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*music.youtube.com/*'",
    args: ["URL"]
  },
  isPlaying: function() {
    var v = document.querySelector('#movie_player video') || document.querySelector('video');
    return v ? (!v.paused && !v.ended) : false;
  },
  toggle: function() {
    var btn = document.querySelector('#play-pause-button, .ytmusic-player-bar.play-pause-button, tp-yt-paper-icon-button.play-pause-button');
    if (btn) { btn.click(); return; }
    var v = document.querySelector('video');
    if (v) { if (v.paused) v.play(); else v.pause(); }
  },
  previous: function() {
    var btn = document.querySelector('.previous-button, .ytmusic-player-bar.previous-button, tp-yt-paper-icon-button.previous-button');
    if (btn) { btn.click(); }
  },
  next: function() {
    var btn = document.querySelector('.next-button, .ytmusic-player-bar.next-button, tp-yt-paper-icon-button.next-button');
    if (btn) { btn.click(); }
  },
  pause: function() {
    var v = document.querySelector('#movie_player video') || document.querySelector('video');
    if (v && !v.paused) {
      var btn = document.querySelector('#play-pause-button, .ytmusic-player-bar.play-pause-button');
      if (btn) { btn.click(); } else { v.pause(); }
    }
  },
  favorite: function() {
    var btn = document.querySelector('ytmusic-like-button-renderer #button-shape-like button, ytmusic-like-button-renderer .like');
    if (btn) { btn.click(); }
  },
  trackInfo: function() {
    var meta = (navigator.mediaSession && navigator.mediaSession.metadata) ? navigator.mediaSession.metadata : null;
    var titleEl = document.querySelector('.title.ytmusic-player-bar');
    var bylineEl = document.querySelector('.byline.ytmusic-player-bar');
    var thumbEl = document.querySelector('.ytmusic-player-bar img');
    var likeEl = document.querySelector('ytmusic-like-button-renderer');
    return {
      'image': (meta && meta.artwork && meta.artwork.length) ? meta.artwork[meta.artwork.length - 1].src : (thumbEl ? thumbEl.src : ''),
      'track': (meta && meta.title) ? meta.title : (titleEl ? titleEl.textContent.trim() : document.title),
      'artist': (meta && meta.artist) ? meta.artist : (bylineEl ? bylineEl.textContent.trim() : 'YouTube Music'),
      'album': (meta && meta.album) ? meta.album : '',
      'favorited': likeEl ? (likeEl.getAttribute('like-status') === 'LIKE') : false
    };
  }
}
