//
//  SoundCloud.js
//  FineTune (BeardedSpice Strategy)
//

BSStrategy = {
  version: 3,
  displayName: "SoundCloud",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*soundcloud.com*'",
    args: ["URL"]
  },
  isPlaying: function () {
    if (navigator.mediaSession && navigator.mediaSession.playbackState === 'playing') return true;
    var play = document.querySelector('.playControl, .playControls__play');
    return play ? play.classList.contains('playing') : false;
  },
  toggle: function () {
    var btn = document.querySelector('.playControl, .playControls__play');
    if (btn) { btn.click(); }
  },
  next: function () {
    var btn = document.querySelector('.skipControl__next');
    if (btn) { btn.click(); }
  },
  favorite: function () {
    var btn = document.querySelector('div.playControls button.playbackSoundBadge__like, .playbackSoundBadge__like');
    if (btn) { btn.click(); }
  },
  previous: function () {
    var btn = document.querySelector('.skipControl__previous');
    if (btn) { btn.click(); }
  },
  pause: function () {
    var play = document.querySelector('.playControl, .playControls__play');
    if (play && play.classList.contains('playing')) { play.click(); }
  },
  trackInfo: function () {
    var metaSession = (navigator.mediaSession && navigator.mediaSession.metadata) ? navigator.mediaSession.metadata : null;
    var meta = document.querySelector('a.playbackSoundBadge__titleLink, a.playbackSoundBadge__title');
    var artistEl = document.querySelector('a.playbackSoundBadge__lightLink');
    var likeBtn = document.querySelector('button.playbackSoundBadge__like');
    return {
      'track': (metaSession && metaSession.title) ? metaSession.title : (meta ? (meta.title || meta.textContent.trim()) : document.title),
      'artist': (metaSession && metaSession.artist) ? metaSession.artist : (artistEl ? artistEl.textContent.trim() : 'SoundCloud'),
      'image': (metaSession && metaSession.artwork && metaSession.artwork.length) ? metaSession.artwork[metaSession.artwork.length - 1].src : '',
      'favorited': likeBtn ? likeBtn.classList.contains('sc-button-selected') : false
    };
  }
}
